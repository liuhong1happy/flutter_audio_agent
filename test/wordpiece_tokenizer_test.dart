/// WordPiece 分词器测试。
///
/// 用**合成小词表**而不是真模型:`tokenizer.json` 有 439KB,不该进仓库,而算法本身的
/// 正确性与词表大小无关。真模型的对照见文件末尾的可选用例(需环境变量指路)。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_tts_demo/utils/memory/wordpiece_tokenizer.dart';

/// 合成词表:每个条目都为了让某条断言能精确成立而存在。
///
/// | token | id | 用途 |
/// |---|---|---|
/// | `[PAD]`/`[UNK]`/`[CLS]`/`[SEP]` | 0–3 | 特殊 token |
/// | `北`/`京`/`你`/`好` | 4–7 | CJK 逐字(验证 handle_chinese_chars) |
/// | `un`/`##aff`/`##able` | 8–10 | 验证 `##` 续接前缀 |
/// | `hello`/`Hello` | 11/12 | 验证 `lowercase:false`(**不是**大小写折叠) |
/// | `,`/`。` | 14/15 | 验证标点独立成 token |
/// | `北京` | 18 | 验证多字 CJK 词条在 handle_chinese_chars 下**不可达** |
const Map<String, int> _vocab = {
  '[PAD]': 0,
  '[UNK]': 1,
  '[CLS]': 2,
  '[SEP]': 3,
  '北': 4,
  '京': 5,
  '你': 6,
  '好': 7,
  'un': 8,
  '##aff': 9,
  '##able': 10,
  'hello': 11,
  'Hello': 12,
  'world': 13,
  ',': 14,
  '。': 15,
  'zz': 16,
  '##z': 17,
  '北京': 18,
};

Map<String, dynamic> _tokenizerJson({int maxChars = 100}) => {
      'model': {
        'type': 'WordPiece',
        'unk_token': '[UNK]',
        'continuing_subword_prefix': '##',
        'max_input_chars_per_word': maxChars,
        'vocab': _vocab,
      },
      'normalizer': {
        'type': 'BertNormalizer',
        'clean_text': true,
        'handle_chinese_chars': true,
        'strip_accents': null,
        // ⚠️ 真模型(`bge-small-zh-v1.5`)也是 false。坑 23:三份配置里
        // `sentence_bert_config.json` 写 true,与 `tokenizer.json` /
        // `tokenizer_config.json` 矛盾,以后两者为准。
        'lowercase': false,
      },
      'pre_tokenizer': {'type': 'BertPreTokenizer'},
    };

void main() {
  final tk = WordPieceTokenizer.fromJson(_tokenizerJson());
  final tkSmall = WordPieceTokenizer.fromJson(_tokenizerJson(maxChars: 3));

  group('① 归一化 + ③ 拼装', () {
    test('CJK 逐字切开,并包 [CLS]/[SEP]', () {
      final r = tk.encode('北京');
      expect(r.inputIds, [2, 4, 5, 3]);
      expect(r.length, 4);
    });

    test('attentionMask 全 1、tokenTypeIds 全 0,长度与 ids 一致', () {
      final r = tk.encode('北京你好');
      expect(r.inputIds.length, 6); // [CLS] 北 京 你 好 [SEP]
      expect(r.attentionMask, everyElement(1));
      expect(r.tokenTypeIds, everyElement(0));
      expect(r.attentionMask.length, r.inputIds.length);
      expect(r.tokenTypeIds.length, r.inputIds.length);
    });

    test('clean_text 丢弃控制字符(NUL)', () {
      expect(tk.encode('北\u0000京').inputIds, tk.encode('北京').inputIds);
    });

    test('clean_text 把各类空白归一为单空格', () {
      expect(tk.encode('北京　你好').inputIds, tk.encode('北京 你好').inputIds);
      expect(tk.encode('北京\t\n你好').inputIds, tk.encode('北京 你好').inputIds);
    });

    test('多字 CJK 词条不可达(CJK 已被逐字拆开,词表里有也匹配不上)', () {
      // 词表里确实有 '北京'=18,但它永远不会被抽出。
      expect(_vocab['北京'], 18);
      final ids = tk.encode('北京').inputIds;
      expect(ids, isNot(contains(18)));
      expect(ids, [2, 4, 5, 3]);
    });
  });

  group('② 预分词:BertPreTokenizer', () {
    test('ASCII 标点独立成 token', () {
      expect(tk.encode('北京,你好').inputIds, [2, 4, 5, 14, 6, 7, 3]);
    });

    test('CJK 标点独立成 token', () {
      expect(tk.encode('北京。').inputIds, [2, 4, 5, 15, 3]);
    });

    test('标点不吞掉相邻词(两侧都被冲刷)', () {
      expect(tk.encode('hello,world').inputIds, [2, 11, 14, 13, 3]);
    });
  });

  group('③ WordPiece 贪心最长匹配', () {
    test('整词命中直接用整词 id', () {
      expect(tk.encode('hello').inputIds, [2, 11, 3]);
    });

    test('未命中整词时用 ## 续接前缀切子词', () {
      // 'unaffable' → un(8) + ##aff(9) + ##able(10)
      expect(tk.encode('unaffable').inputIds, [2, 8, 9, 10, 3]);
    });

    test('lowercase=false:大小写**不**折叠,Hello 走自己的词条', () {
      // 关键回归:若误按 lowercase=true 处理,'Hello' 会先变成 'hello' 再命中 11。
      expect(tk.encode('Hello').inputIds, [2, 12, 3]);
      expect(tk.encode('Hello').inputIds, isNot(contains(11)));
    });

    test('完全无法匹配 → [UNK]', () {
      expect(tk.encode('xyz').inputIds, [2, 1, 3]);
    });

    test('超过 max_input_chars_per_word 的词整体判 UNK', () {
      // 'unaffable' 有 9 个字符,小词表上限为 3。
      expect(tkSmall.encode('unaffable').inputIds, [2, 1, 3]);
    });

    test('恰在上限内的词仍正常切分', () {
      // 'zzz' 3 字符 = 上限 3,不触发 UNK 短路;zz(16)+##z(17)。
      expect(tkSmall.encode('zzz').inputIds, [2, 16, 17, 3]);
    });
  });

  group('截断与批处理', () {
    test('内容超出 maxTokens 时从尾部截断,特殊 token 仍保留', () {
      final r = tk.encode('北京你好', maxTokens: 2);
      expect(r.inputIds, [2, 4, 5, 3]);
      expect(r.length, 4);
    });

    test('默认内容上限 = 510(max_position_embeddings 512 减去两个特殊 token)', () {
      expect(WordPieceTokenizer.maxContentTokens, 510);
      // 恰好的长度不应被截断:用短文本验证边界语义(内容 <= 上限 ⇒ 原样)。
      final ids = tk.encode('北京', maxTokens: 2).inputIds;
      expect(ids, [2, 4, 5, 3]);
    });

    test('批处理补齐到批内最长,且 PAD 在 [SEP] 之后、mask 置 0', () {
      final batch = tk.encodeBatch(['北京', '北京你好']);
      expect(batch.length, 2);
      // 两条都被补齐到 6
      expect(batch[0].inputIds.length, 6);
      expect(batch[1].inputIds.length, 6);
      // [CLS] 北 京 [SEP] PAD PAD
      expect(batch[0].inputIds, [2, 4, 5, 3, 0, 0]);
      expect(batch[0].attentionMask, [1, 1, 1, 1, 0, 0]);
      expect(batch[0].tokenTypeIds, everyElement(0));
      // 最长的一条不被改动
      expect(batch[1].inputIds, [2, 4, 5, 6, 7, 3]);
      expect(batch[1].attentionMask, everyElement(1));
    });

    test('批内等长时不做任何补齐', () {
      final batch = tk.encodeBatch(['北京', '你好']);
      expect(batch[0].inputIds, [2, 4, 5, 3]);
      expect(batch[1].inputIds, [2, 6, 7, 3]);
    });
  });

  group('decode 往返', () {
    test('CJK 逐字 token 以空格拼接(逐字切分的必然结果)', () {
      expect(tk.decode([2, 4, 5, 3]), '北 京');
    });

    test('## 续接片段无空格拼接,还原原词', () {
      expect(tk.decode([2, 8, 9, 10, 3]), 'unaffable');
    });

    test('跳过 [CLS]/[SEP]/[PAD]', () {
      expect(tk.decode([2, 11, 3, 0, 0]), 'hello');
    });
  });

  group('健壮性:配置不对要**响亮报错**,不要静默走错分支', () {
    test('非 WordPiece(如 BPE)直接抛错', () {
      final json = _tokenizerJson();
      (json['model'] as Map<String, dynamic>)['type'] = 'BPE';
      expect(
        () => WordPieceTokenizer.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('vocab 缺少 [CLS] 抛错', () {
      final json = _tokenizerJson();
      // 词表是 const(不可变),这里显式复制一份再删,避免改动共享的测试夹具。
      final vocab = Map<String, int>.from(_vocab)..remove('[CLS]');
      (json['model'] as Map<String, dynamic>)['vocab'] = vocab;
      expect(
        () => WordPieceTokenizer.fromJson(json),
        throwsA(isA<FormatException>()),
      );
    });

    test('缺少 model 段抛错', () {
      expect(
        () => WordPieceTokenizer.fromJson({'normalizer': {}}),
        throwsA(isA<FormatException>()),
      );
    });

    test('fromJsonString 对非对象顶层抛错', () {
      expect(
        () => WordPieceTokenizer.fromJsonString('[]'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('真模型对照:bge-small-zh-v1.5 的 tokenizer.json', () {
    // 夹具说明:
    // - `bge_tokenizer.json` 是模型自带的 `tokenizer.json`(439KB,与仓库里 5.4MB 的
    //   `assets/dict.txt` 同量级,故入库作为夹具),只作**测试**用,运行时仍从
    //   ModelScope 下载。
    // - `bge_ref_ids.json` 是**权威参考输出**,由 transformers.js(官方 Rust tokenizers,
    //   与 HF Python 同源)在同一份 tokenizer.json 上生成。它是本文件最重要的断言依据 ——
    //   分词错了不会抛异常,只会让检索质量静默变差,所以必须逐 token 对齐。
    final real = WordPieceTokenizer.fromJsonString(
      File('test/fixtures/bge_tokenizer.json').readAsStringSync(),
    );
    final reference = (jsonDecode(
      File('test/fixtures/bge_ref_ids.json').readAsStringSync(),
    ) as List)
        .cast<Map<String, dynamic>>();

    test('词表与特殊 token 与真模型一致', () {
      expect(real.vocabSize, 21128);
      expect(real.padId, 0);
      expect(real.unkId, 100);
      expect(real.clsId, 101);
      expect(real.sepId, 102);
      expect(real.continuingSubwordPrefix, '##');
      expect(real.maxInputCharsPerWord, 100);
      // 真模型必须是 lowercase=false —— 三份配置里只有 sentence_bert_config.json 写 true,
      // 且已用行为验证(见下条 'Hello' → [UNK])。
      expect(real.lowercase, isFalse);
      expect(real.stripAccents, isFalse);
    });

    test('真词表逐条比对:与 transformers.js 参考输出**完全一致**', () {
      expect(reference, isNotEmpty);
      // 参考输出未截断(truncation:false),故这里放宽上限后再比。
      const noTruncate = 100000;
      for (final item in reference) {
        final text = item['text'] as String;
        final expected = (item['ids'] as List).cast<int>();
        final actual = real.encode(text, maxTokens: noTruncate).inputIds;
        expect(
          actual,
          expected,
          reason: '文本对不上: ${jsonEncode(text)}',
        );
      }
    });

    test('大写 Hello 是真 UNK(行为层面证实 lowercase=false)', () {
      // 若误按 lowercase=true,会先折叠成 'hello' 并命中其 id,而不是 [UNK]。
      final ref = reference.firstWhere((e) => e['text'] == 'Hello');
      expect((ref['ids'] as List), [101, 100, 102]);
      expect(real.encode('Hello').inputIds, [101, 100, 102]);
      // 小写则是正常词条,反证词表里只有小写形式。
      expect(real.encode('hello').inputIds, isNot(contains(100)));
    });

    test('中文逐字命中,不产生 UNK', () {
      final ids = real.encode('今天天气很好').inputIds;
      expect(ids.first, 101);
      expect(ids.last, 102);
      expect(ids.sublist(1, ids.length - 1), isNot(contains(100)));
      expect(ids.length, 8); // [CLS] + 6 字 + [SEP]
    });

    test('默认上限 510 生效:超长文本被截断到 512 总长', () {
      final long = '一个非常长的句子用来测试截断行为${'的' * 600}';
      expect(real.encode(long).length, 512);
      expect(real.encode(long).inputIds.last, 102); // 截断后 [SEP] 仍在末尾
      // 放宽上限则不被截断,说明截断确实来自 maxTokens 而非别处。
      expect(real.encode(long, maxTokens: 100000).length, greaterThan(512));
    });

    test('往返:中文逐字 token 去空格后还原原句', () {
      const text = '今天天气很好';
      final ids = real.encode(text).inputIds;
      final content = ids.sublist(1, ids.length - 1);
      expect(real.decode(content).replaceAll(' ', ''), text);
    });
  });
}
