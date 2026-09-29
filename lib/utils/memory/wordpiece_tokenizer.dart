/// 纯 Dart 实现的 BERT WordPiece 分词器(读 HuggingFace `tokenizer.json`)。
///
/// ⚠️ **角色说明(实施后变更)**:生产路径**不再使用**本文件 —— 实际推理走
/// `flutter_embedder` 内置的 HF `tokenizers`(Rust),它自己解析同一个
/// `tokenizer.json`。本实现现在的作用是**测试参照物**:
/// `test/kb_chunker_test.dart` 用它验证"KbChunker 的 500 字符预算确实落在
/// 模型 510 token 上限之内" —— 这是唯一能真正校验该预算的手段
/// (字符数只是 token 数的上界,不能替代实测)。
/// 因此**不要删**:删了那个断言就只剩弱化的字符数检查,预算失守将无人发现。
///
/// 为什么自己写:`transformers` 生态没有可用的纯 Dart 包,而 BERT 分词逻辑很小且
/// **完全确定**,自实现比引依赖更可控、可测。
///
/// 严格对齐 HF `BertTokenizer` 的四步流水线:
///   ① BertNormalizer  → ② BertPreTokenizer → ③ WordPiece → ④ TemplateProcessing
///
/// 本文件只服务 `bge-small-zh-v1.5`,其参数(全部从 `tokenizer.json` 实测,勿凭记忆):
///   - `normalizer` = BertNormalizer `clean_text:true` `handle_chinese_chars:true`
///     `strip_accents:null` **`lowercase:false`**
///     ⚠️ `lowercase` 的三份配置里 `sentence_bert_config.json` 写的是 `true`,与
///     `tokenizer_config.json` / `tokenizer.json` 的 `false` **矛盾**。以后两者为准
///     (`tokenizer.json` 是运行时的权威来源),别照抄 sentence-transformers 那份遗留默认值。
///   - `pre_tokenizer` = BertPreTokenizer(空白切 + 标点独立成 token)
///   - `model.type` = WordPiece,`unk_token` = `[UNK]`,`continuing_subword_prefix` = `##`,
///     `max_input_chars_per_word` = 100,vocab 21128
///   - 特殊 token id:`[PAD]`=0 `[UNK]`=100 `[CLS]`=101 `[SEP]`=102
///   - `post_processor` = TemplateProcessing `[CLS] A [SEP]`,两者 type_id 均为 0
// 构造器用命名参数 + 显式赋值(私有字段不能作命名形参),与 app_dependencies.dart 同约定。
// ignore_for_file: prefer_initializing_formals
library;

import 'dart:convert';
import 'dart:io';

/// 一条分词结果。
class TokenizedInput {
  const TokenizedInput({
    required this.inputIds,
    required this.attentionMask,
    required this.tokenTypeIds,
  });

  /// `[CLS] ... [SEP]`,长度 = 内容 token 数 + 2。
  final List<int> inputIds;

  /// 与 [inputIds] 等长,本实现单条推理恒为 1(批处理时由调用方补 0)。
  final List<int> attentionMask;

  /// 与 [inputIds] 等长,单句恒 0(`type_vocab_size`=2 但单句不用第二类)。
  final List<int> tokenTypeIds;

  int get length => inputIds.length;

  @override
  String toString() => 'TokenizedInput(len=${inputIds.length})';
}

class WordPieceTokenizer {
  WordPieceTokenizer._({
    required Map<String, int> vocab,
    required List<String> idToToken,
    required this.unkToken,
    required this.continuingSubwordPrefix,
    required this.maxInputCharsPerWord,
    required this.clsId,
    required this.sepId,
    required this.padId,
    required this.unkId,
    required this.lowercase,
    required this.stripAccents,
    required this.cleanText,
    required this.handleChineseChars,
  })  : _vocab = vocab,
        _idToToken = idToToken;

  final Map<String, int> _vocab;
  final List<String> _idToToken;

  final String unkToken;
  final String continuingSubwordPrefix;
  final int maxInputCharsPerWord;

  final int clsId;
  final int sepId;
  final int padId;
  final int unkId;

  final bool lowercase;
  final bool stripAccents;
  final bool cleanText;
  final bool handleChineseChars;

  int get vocabSize => _vocab.length;

  /// 内容 token 上限:`max_position_embeddings`(512)减去 `[CLS]`/`[SEP]`。
  ///
  /// ⚠️ 超长必须截断 —— BGE 的 `max_position_embeddings` 是 512,且含两个特殊 token。
  static const int maxContentTokens = 510;

  /// 从 `tokenizer.json` 文件加载。
  static Future<WordPieceTokenizer> fromFile(String path) async {
    final text = await File(path).readAsString();
    return fromJsonString(text);
  }

  /// 从 `tokenizer.json` 的 JSON 字符串加载。
  static WordPieceTokenizer fromJsonString(String jsonText) {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('tokenizer.json 顶层不是 JSON 对象');
    }
    return fromJson(decoded);
  }

  /// 从已解析的 `tokenizer.json` 构建。
  static WordPieceTokenizer fromJson(Map<String, dynamic> json) {
    final model = json['model'];
    if (model is! Map<String, dynamic>) {
      throw const FormatException('tokenizer.json 缺少 model 段');
    }
    if (model['type'] != 'WordPiece') {
      // 明确报错而不是猜:换成 BPE/Unigram 的分词逻辑完全不同。
      throw FormatException('只支持 WordPiece,实际为 ${model['type']}');
    }
    final rawVocab = model['vocab'];
    if (rawVocab is! Map) {
      throw const FormatException('tokenizer.json 缺少 model.vocab');
    }

    final vocab = <String, int>{};
    var maxId = -1;
    rawVocab.forEach((k, v) {
      final token = k as String;
      final id = (v as num).toInt();
      vocab[token] = id;
      if (id > maxId) maxId = id;
    });
    final idToToken = List<String>.filled(maxId + 1, '');
    vocab.forEach((token, id) => idToToken[id] = token);

    // BertNormalizer 参数(缺失时按 HF 的默认值处理)。
    final normalizer = json['normalizer'];
    var lowercase = false;
    var stripAccents = false;
    var cleanText = false;
    var handleChineseChars = false;
    if (normalizer is Map<String, dynamic> &&
        normalizer['type'] == 'BertNormalizer') {
      lowercase = normalizer['lowercase'] == true;
      // ⚠️ `strip_accents: null` 一律按 false 处理:HF 在 do_lower_case=false 时
      // 不会去重音,而本模型正是 lowercase=false。
      stripAccents = normalizer['strip_accents'] == true;
      cleanText = normalizer['clean_text'] == true;
      handleChineseChars = normalizer['handle_chinese_chars'] == true;
    }

    int specialId(String token) {
      final id = vocab[token];
      if (id == null) {
        throw FormatException('tokenizer.json 的 vocab 缺少特殊 token $token');
      }
      return id;
    }

    return WordPieceTokenizer._(
      vocab: vocab,
      idToToken: idToToken,
      unkToken: (model['unk_token'] as String?) ?? '[UNK]',
      continuingSubwordPrefix:
          (model['continuing_subword_prefix'] as String?) ?? '##',
      maxInputCharsPerWord:
          (model['max_input_chars_per_word'] as num?)?.toInt() ?? 100,
      clsId: specialId('[CLS]'),
      sepId: specialId('[SEP]'),
      padId: vocab['[PAD]'] ?? 0,
      unkId: specialId('[UNK]'),
      lowercase: lowercase,
      stripAccents: stripAccents,
      cleanText: cleanText,
      handleChineseChars: handleChineseChars,
    );
  }

  /// 完整编码:归一化 → 预分词 → WordPiece → 拼 `[CLS]`/`[SEP]`。
  ///
  /// [maxTokens] 为**内容** token 上限(不含两个特殊 token),超出则从尾部截断。
  TokenizedInput encode(String text, {int maxTokens = maxContentTokens}) {
    final pieces = _tokenize(text);
    final content = pieces.length > maxTokens
        ? pieces.sublist(0, maxTokens)
        : pieces;
    final ids = <int>[clsId, ...content, sepId];
    return TokenizedInput(
      inputIds: ids,
      attentionMask: List<int>.filled(ids.length, 1),
      tokenTypeIds: List<int>.filled(ids.length, 0),
    );
  }

  /// 批量编码,并按批内最长补齐到等长(`attentionMask` 补 0)。
  ///
  /// 一次前向跑多块是必须的:逐块调用会让 1000 块 = 1000 次前向。
  /// 补齐到批内最长(而非全局 512)可以省掉大量无用的 attention 计算。
  List<TokenizedInput> encodeBatch(
    List<String> texts, {
    int maxTokens = maxContentTokens,
  }) {
    final encoded = texts.map((t) => encode(t, maxTokens: maxTokens)).toList();
    var maxLen = 0;
    for (final e in encoded) {
      if (e.length > maxLen) maxLen = e.length;
    }
    return encoded.map((e) {
      if (e.length == maxLen) return e;
      final pad = maxLen - e.length;
      return TokenizedInput(
        inputIds: [...e.inputIds, ...List<int>.filled(pad, padId)],
        attentionMask: [...e.attentionMask, ...List<int>.filled(pad, 0)],
        tokenTypeIds: [...e.tokenTypeIds, ...List<int>.filled(pad, 0)],
      );
    }).toList();
  }

  /// 只做内容 token 化(不含特殊 token),便于单测与调试。
  List<int> tokenizeToIds(String text) => _tokenize(text);

  /// 反解 token id → 文本(用于往返校验)。跳过特殊 token。
  String decode(List<int> ids) {
    final buffer = StringBuffer();
    for (final id in ids) {
      if (id == clsId || id == sepId || id == padId) continue;
      final token = id >= 0 && id < _idToToken.length ? _idToToken[id] : '';
      if (token.isEmpty) continue;
      if (token.startsWith(continuingSubwordPrefix)) {
        buffer.write(token.substring(continuingSubwordPrefix.length));
      } else {
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(token);
      }
    }
    return buffer.toString();
  }

  // ── ① 归一化(BertNormalizer)────────────────────────────────────────

  String _normalize(String text) {
    final out = StringBuffer();
    for (final rune in text.runes) {
      if (cleanText) {
        // 丢弃 NUL / U+FFFD / 控制字符(照 HF `_clean_text`)。
        if (rune == 0 || rune == 0xFFFD || _isControl(rune)) continue;
        if (_isWhitespace(rune)) {
          out.write(' ');
          continue;
        }
      }
      if (handleChineseChars && _isChineseChar(rune)) {
        // CJK 字符前后补空格 ⇒ 后续每个汉字独立成 token。
        out.write(' ');
        out.writeCharCode(rune);
        out.write(' ');
      } else {
        out.writeCharCode(rune);
      }
    }
    var s = out.toString();
    if (lowercase) s = s.toLowerCase();
    if (stripAccents) s = _stripAccents(s);
    return s;
  }

  static bool _isWhitespace(int cp) {
    if (cp == 0x20 || cp == 0x09 || cp == 0x0A || cp == 0x0D) return true;
    // Zs 类(Unicode 空格分隔符)。
    return cp == 0xA0 ||
        cp == 0x1680 ||
        (cp >= 0x2000 && cp <= 0x200A) ||
        cp == 0x202F ||
        cp == 0x205F ||
        cp == 0x3000;
  }

  static bool _isControl(int cp) {
    if (cp == 0x09 || cp == 0x0A || cp == 0x0D) return false; // \t \n \r 保留
    if (cp <= 0x1F || (cp >= 0x7F && cp <= 0x9F)) return true; // Cc
    // Cf(格式字符)常用区段。
    return (cp >= 0x200B && cp <= 0x200F) ||
        (cp >= 0x202A && cp <= 0x202E) ||
        (cp >= 0x2060 && cp <= 0x2064) ||
        cp == 0xFEFF;
  }

  /// CJK 判定(照 HF `_is_chinese_char` 的区段)。
  static bool _isChineseChar(int cp) {
    return (cp >= 0x4E00 && cp <= 0x9FFF) ||
        (cp >= 0x3400 && cp <= 0x4DBF) ||
        (cp >= 0x20000 && cp <= 0x2A6DF) ||
        (cp >= 0x2A700 && cp <= 0x2B73F) ||
        (cp >= 0x2B740 && cp <= 0x2B81F) ||
        (cp >= 0x2B820 && cp <= 0x2CEAF) ||
        (cp >= 0xF900 && cp <= 0xFAFF) ||
        (cp >= 0x2F800 && cp <= 0x2FA1F);
  }

  /// ⚠️ 近似实现:只覆盖 Latin-1 Supplement 与 Latin Extended-A 的常见重音字母。
  /// 本模型 `strip_accents` 为 false,此路径实际不启用;若将来换成启用重音的模型,
  /// 这里需要补全 Unicode NFD 分解(Dart 无内置 NFD)。
  static String _stripAccents(String s) {
    final buffer = StringBuffer();
    for (final rune in s.runes) {
      buffer.write(_accentMap[rune] ?? String.fromCharCode(rune));
    }
    return buffer.toString();
  }

  static const Map<int, String> _accentMap = {
    0x00C0: 'A', 0x00C1: 'A', 0x00C2: 'A', 0x00C3: 'A', 0x00C4: 'A',
    0x00C5: 'A', 0x00C7: 'C', 0x00C8: 'E', 0x00C9: 'E', 0x00CA: 'E',
    0x00CB: 'E', 0x00CC: 'I', 0x00CD: 'I', 0x00CE: 'I', 0x00CF: 'I',
    0x00D1: 'N', 0x00D2: 'O', 0x00D3: 'O', 0x00D4: 'O', 0x00D5: 'O',
    0x00D6: 'O', 0x00D9: 'U', 0x00DA: 'U', 0x00DB: 'U', 0x00DC: 'U',
    0x00DD: 'Y', 0x00E0: 'a', 0x00E1: 'a', 0x00E2: 'a', 0x00E3: 'a',
    0x00E4: 'a', 0x00E5: 'a', 0x00E7: 'c', 0x00E8: 'e', 0x00E9: 'e',
    0x00EA: 'e', 0x00EB: 'e', 0x00EC: 'i', 0x00ED: 'i', 0x00EE: 'i',
    0x00EF: 'i', 0x00F1: 'n', 0x00F2: 'o', 0x00F3: 'o', 0x00F4: 'o',
    0x00F5: 'o', 0x00F6: 'o', 0x00F9: 'u', 0x00FA: 'u', 0x00FB: 'u',
    0x00FC: 'u', 0x00FD: 'y', 0x00FF: 'y',
  };

  // ── ② 预分词(BertPreTokenizer)+ ③ WordPiece ────────────────────────

  List<int> _tokenize(String text) {
    final normalized = _normalize(text);
    final out = <int>[];
    final buffer = StringBuffer();

    void flush() {
      if (buffer.isEmpty) return;
      out.addAll(_wordPiece(buffer.toString()));
      buffer.clear();
    }

    for (final rune in normalized.runes) {
      if (_isWhitespace(rune)) {
        flush();
      } else if (_isPunctuation(rune)) {
        // 标点独立成 token(先冲刷已累积的词)。
        flush();
        out.addAll(_wordPiece(String.fromCharCode(rune)));
      } else {
        buffer.writeCharCode(rune);
      }
    }
    flush();
    return out;
  }

  /// 标点判定。
  ///
  /// ⚠️ 近似实现:Dart 的 `RegExp` 不支持 `\p{P}` 这类 Unicode 属性转义,无法直接
  /// 用 Unicode P* 类别,因此这里用**区段表**覆盖现实输入会用到的范围
  /// (ASCII / Latin-1 / 常用符号 / CJK 标点 / 全角)。生僻标点可能被当成普通字符
  /// 并进词里 —— 影响的是 token 边界而非正确性,且编解码两侧**同一实现**,不会不一致。
  static bool _isPunctuation(int cp) {
    // ASCII 标点
    if (cp >= 0x21 && cp <= 0x2F) return true;
    if (cp >= 0x3A && cp <= 0x40) return true;
    if (cp >= 0x5B && cp <= 0x60) return true;
    if (cp >= 0x7B && cp <= 0x7E) return true;
    // Latin-1 常见标点
    if (cp == 0xA1 || cp == 0xA7 || cp == 0xAB || cp == 0xB6 || cp == 0xB7) {
      return true;
    }
    if (cp == 0xBB || cp == 0xBF) return true;
    // General Punctuation(排除 0x2000-0x200A 的空白与 0x200B-0x200F 的格式符)
    if (cp >= 0x2010 && cp <= 0x2027) return true;
    if (cp >= 0x2030 && cp <= 0x205E) return true;
    // CJK 符号与标点(0x3000 是表意空格,已在 _isWhitespace 处理)
    if (cp >= 0x3001 && cp <= 0x303F) return true;
    // 全角 ASCII 变体
    if (cp >= 0xFF01 && cp <= 0xFF0F) return true;
    if (cp >= 0xFF1A && cp <= 0xFF20) return true;
    if (cp >= 0xFF3B && cp <= 0xFF40) return true;
    if (cp >= 0xFF5B && cp <= 0xFF65) return true;
    return false;
  }

  /// 贪心最长匹配的 WordPiece。
  List<int> _wordPiece(String word) {
    if (word.isEmpty) return const [];
    // 超长词整体判为 UNK(照 HF:max_input_chars_per_word)。
    if (word.runes.length > maxInputCharsPerWord) return [unkId];

    final chars = word.runes.map(String.fromCharCode).toList();
    final ids = <int>[];
    var start = 0;
    while (start < chars.length) {
      var end = chars.length;
      int? matched;
      while (start < end) {
        final piece = chars.sublist(start, end).join();
        final candidate =
            start > 0 ? '$continuingSubwordPrefix$piece' : piece;
        final id = _vocab[candidate];
        if (id != null) {
          matched = id;
          break;
        }
        end--;
      }
      if (matched == null) {
        // 整词判为 UNK(HF 的行为:一个子词匹配不上就丢弃整词结果)。
        return [unkId];
      }
      ids.add(matched);
      start = end;
    }
    return ids;
  }
}
