/// 知识库切块(**检索导向**)。
///
/// ⚠️ **刻意不复用 `utils/text_chunker.dart`**。那个是服务 **TTS** 的:首句 `1+4+10` 词、
/// 后续整句 ≤20 词,目标是「合成不卡顿、朗读自然」。对**检索**而言这套策略是错的 ——
/// 块太碎会让单块语义不完整、命中率下降。两者目标相反,不可互用。
///
/// 本切块器策略:
///   ① 先按 **markdown 标题 / 空行段落**切(语义边界);
///   ② 小块向后合并,直到再加一块就超预算;
///   ③ 单块超预算时按**句末标点**二次切,不倒断句子;
///   ④ 单句仍超预算时退化为**按字符硬切**(标记出来,便于排查);
///   ⑤ 相邻块**重叠 ~15%**,且重叠起点吸附到句子边界,避免答案恰好跨在边界上。
///
/// 预算单位是 **BERT token**,由 [countTokens] 度量。默认实现用字符串长度,它是
/// **安全的上界**(每个 token 至少覆盖 1 个字符 ⇒ token 数 ≤ 字符数),因此永不越界;
/// 生产环境应传入真实分词器以获得更紧的排布。
library;

import 'dart:math' as math;

/// 一段待入库的知识块。
class KbChunk {
  const KbChunk({
    required this.seq,
    required this.text,
    required this.charStart,
    required this.charEnd,
    this.hardSplit = false,
  });

  /// 文档内序号(从 0 开始)。
  final int seq;

  final String text;

  /// 在原始文档中的字符区间 `[charStart, charEnd)`(不含重叠部分)。
  final int charStart;
  final int charEnd;

  /// 是否因单句超长而**按字符硬切**(正常文档应为 false)。
  final bool hardSplit;

  int get length => text.length;

  @override
  String toString() =>
      'KbChunk(seq=$seq, len=$length, [$charStart,$charEnd)${hardSplit ? ', HARD' : ''})';
}

/// token 计数函数。默认见 [defaultTokenCount]。
typedef TokenCount = int Function(String text);

/// 默认计数:**字符数**。它是真实 BERT token 数的**上界**
/// (任何 token 都至少覆盖一个字符),故用它与预算比较永不越界。
int defaultTokenCount(String text) => text.length;

/// 检索导向的切块器。
class KbChunker {
  KbChunker({
    this.maxTokens = 500,
    this.overlapRatio = 0.15,
    TokenCount? countTokens,
  })  : countTokens = countTokens ?? defaultTokenCount,
        assert(maxTokens > 0),
        assert(overlapRatio >= 0 && overlapRatio < 1);

  /// 单块 token 上限。
  ///
  /// 默认 500 而非模型的 510:留一点余量,避免"估算刚好卡在边界"时被引擎截断
  /// (截断是静默丢尾部内容,最不该发生的事)。
  final int maxTokens;

  /// 相邻块重叠比例(相对 [maxTokens])。
  final double overlapRatio;

  final TokenCount countTokens;

  /// 句末标点(中英文)。用于二次切分与重叠吸附。
  static const String _sentenceEnders = '。!?;.!?;…\n';

  /// 把一篇文档切成若干块。
  List<KbChunk> chunk(String text) {
    if (text.trim().isEmpty) return const [];

    final blocks = _splitBlocks(text);
    final pieces = <_Piece>[];
    for (final b in blocks) {
      pieces.addAll(_fitBlock(b));
    }
    if (pieces.isEmpty) return const [];

    return _mergeWithOverlap(pieces);
  }

  // ── ① 按标题 / 空行段落切 ───────────────────────────────────────────

  /// ⚠️ 这里**刻意不剥离 `\r`** —— 内部文本必须与源文本逐字符对应,否则
  /// 由 `text.length` 推出的块区间会整体短算(CRLF 文档会因此在相邻块之间留出
  /// 未被覆盖的空隙)。`\r` 只在最终产出 [KbChunk.text] 时清理。
  List<_Piece> _splitBlocks(String text) {
    final out = <_Piece>[];
    final lines = text.split('\n');
    var offset = 0;
    final buffer = StringBuffer();
    var bufStart = 0;

    void flush() {
      final s = buffer.toString();
      if (s.trim().isNotEmpty) {
        // end = bufStart + 已写入字符数。仅当"写入内容与源文本逐字符对应"时成立,
        // 故此处既不剥离 '\r',也不给最后一行追加源文本里不存在的尾随换行。
        out.add(_Piece(s, bufStart, bufStart + s.length));
      }
      buffer.clear();
    }

    for (final line in lines) {
      final isHeading = _isHeading(line);
      final isBlank = line.trim().isEmpty;

      // 标题另起一块,保证它与后续内容同块但不与前面内容粘连。
      if (isHeading && buffer.isNotEmpty) flush();

      if (isBlank) {
        flush();
      } else {
        if (buffer.isEmpty) {
          bufStart = offset;
        } else {
          buffer.write('\n'); // 行间分隔符(源文本中确实存在)
        }
        buffer.write(line);
      }
      offset += line.length + 1;
    }
    flush();
    return out;
  }

  /// 产出块文本时清理行尾 `\r`(CRLF 文档)。区间坐标不受影响。
  static String _cleanText(String s) =>
      s.contains('\r') ? s.replaceAll('\r', '') : s;

  static bool _isHeading(String line) {
    final t = line.trimLeft();
    if (t.isEmpty) return false;
    // markdown ATX 标题
    if (t.startsWith('#')) return true;
    // 短行且以常见"标题式"结尾的独立行(如 "第一章 概述")
    return false;
  }

  // ── ② / ③ / ④ 让单块落进预算 ───────────────────────────────────────

  List<_Piece> _fitBlock(_Piece block) {
    if (countTokens(block.text) <= maxTokens) return [block];

    // ③ 按句子切,再贪心合并句子。
    final sentences = _splitSentences(block.text, block.start);
    if (sentences.length > 1) {
      final out = <_Piece>[];
      final buf = StringBuffer();
      var bufStart = sentences.first.start;

      void flush() {
        final s = buf.toString();
        if (s.trim().isNotEmpty) out.add(_Piece(s, bufStart, bufStart + s.length));
        buf.clear();
      }

      for (final s in sentences) {
        final candidate = buf.toString() + s.text;
        if (buf.isNotEmpty && countTokens(candidate) > maxTokens) {
          flush();
          bufStart = s.start;
        }
        // ④ 单句本身就超预算:硬切。
        if (countTokens(s.text) > maxTokens) {
          flush();
          out.addAll(_hardSplit(s));
          bufStart = s.start + s.text.length;
          continue;
        }
        buf.write(s.text);
      }
      flush();
      return out;
    }

    // 整块就是一句(或没有句末标点):硬切。
    return _hardSplit(block);
  }

  /// 逐句切分,保留每句在原文中的起点。
  List<_Piece> _splitSentences(String text, int baseOffset) {
    final out = <_Piece>[];
    var start = 0;
    for (var i = 0; i < text.length; i++) {
      if (_sentenceEnders.contains(text[i])) {
        // 连续标点(如 "……"、"?!")并入本句结尾。
        var end = i + 1;
        while (end < text.length && _sentenceEnders.contains(text[end])) {
          end++;
        }
        final s = text.substring(start, end);
        if (s.isNotEmpty) out.add(_Piece(s, baseOffset + start, baseOffset + end));
        start = end;
        i = end - 1;
      }
    }
    if (start < text.length) {
      final s = text.substring(start);
      out.add(_Piece(s, baseOffset + start, baseOffset + text.length));
    }
    // 合并"过短"的句子片段(仅标点/空白),避免产生无意义碎片。
    return out.where((p) => p.text.trim().isNotEmpty).toList();
  }

  /// ④ 兜底:按字符硬切。正常文档不该走到这里。
  List<_Piece> _hardSplit(_Piece p) {
    final limit = math.max(1, maxTokens);
    final out = <_Piece>[];
    for (var i = 0; i < p.text.length; i += limit) {
      final end = math.min(i + limit, p.text.length);
      out.add(_Piece(
        p.text.substring(i, end),
        p.start + i,
        p.start + end,
        hardSplit: true,
      ));
    }
    return out;
  }

  // ── ⑤ 合并相邻块并加重叠 ───────────────────────────────────────────

  List<KbChunk> _mergeWithOverlap(List<_Piece> pieces) {
    final out = <KbChunk>[];
    var i = 0;
    var prevBody = '';

    while (i < pieces.length) {
      // 1) 先吞并**正文**(不含重叠前缀)。
      //    第一个片段无条件纳入 —— 否则"上一块重叠 + 本块首片段"超预算时会被跳过,
      //    造成**静默丢内容**(曾经就是这么错的)。
      final bodyBuf = StringBuffer();
      var charEnd = pieces[i].end;
      var hardSplit = false;
      var j = i;
      while (j < pieces.length) {
        final candidate = bodyBuf.toString() + pieces[j].text;
        if (j > i && countTokens(candidate) > maxTokens) break;
        bodyBuf.write(pieces[j].text);
        charEnd = pieces[j].end;
        if (pieces[j].hardSplit) hardSplit = true;
        j++;
      }
      final body = bodyBuf.toString();

      // 2) 再算前缀 = 上一块尾部,且按**正文剩余预算**夹紧;夹不下就不加重叠。
      final room = maxTokens - countTokens(body);
      final prefix = room > 0 ? _overlapTail(prevBody, room) : '';

      out.add(KbChunk(
        seq: out.length,
        text: _cleanText(prefix + body),
        charStart: pieces[i].start,
        charEnd: charEnd,
        hardSplit: hardSplit,
      ));

      prevBody = body;
      i = j;
    }
    return out;
  }

  /// 取 [text] 尾部不超过 [budget] 个 token 的内容,起点吸附到句子边界。
  ///
  /// 先按字符切(字符数 ≥ token 数,故不越界),再**向后**吸附到句子边界 ——
  /// 向后吸附只会让尾巴更短,不会突破 [budget]。
  String _overlapTail(String text, int budget) {
    final want = math.min(budget, (maxTokens * overlapRatio).round());
    if (want <= 0 || text.length <= want) return '';

    var start = text.length - want;
    for (var i = start; i < text.length; i++) {
      if (_sentenceEnders.contains(text[i]) && i + 1 < text.length) {
        start = i + 1;
        break;
      }
    }
    return text.substring(start);
  }
}

/// 内部:带原文偏移的文本片段。
class _Piece {
  const _Piece(this.text, this.start, this.end, {this.hardSplit = false});

  final String text;
  final int start;
  final int end;
  final bool hardSplit;

  @override
  String toString() => '_Piece([$start,$end) len=${text.length})';
}
