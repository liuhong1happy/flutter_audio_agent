/// 知识库切块测试(检索导向)。
///
/// 最重要的一条是**不丢内容**:切块出错时用户完全无感 —— 只是"检索不到那一句",
/// 没有任何报错。所以这里用"字符区间并集覆盖全文非空白字符"来硬性守住。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_tts_demo/utils/memory/kb_chunker.dart';
import 'package:flutter_tts_demo/utils/memory/wordpiece_tokenizer.dart';

/// 断言"块的字符区间并集"覆盖了原文所有非空白字符。
///
/// 区间不含重叠部分(见 [KbChunk]),所以这能同时抓出"重叠被算成内容"的假象。
void expectFullCoverage(String source, List<KbChunk> chunks) {
  final covered = List<bool>.filled(source.length, false);
  for (final c in chunks) {
    for (var i = c.charStart; i < c.charEnd && i < source.length; i++) {
      covered[i] = true;
    }
  }
  final missed = <int>[];
  for (var i = 0; i < source.length; i++) {
    if (source[i].trim().isEmpty) continue; // 空白允许落在块外
    if (!covered[i]) missed.add(i);
  }
  expect(
    missed,
    isEmpty,
    reason: '有 ${missed.length} 个非空白字符未被任何块覆盖,'
        '首个在偏移 ${missed.isEmpty ? -1 : missed.first}:'
        '「${missed.isEmpty ? '' : source.substring(missed.first, (missed.first + 20).clamp(0, source.length))}」',
  );
}

void main() {
  group('基本行为', () {
    test('空 / 纯空白 → 无块', () {
      final c = KbChunker();
      expect(c.chunk(''), isEmpty);
      expect(c.chunk('   \n\n \t '), isEmpty);
    });

    test('短文档 → 单块,seq 从 0 开始', () {
      final c = KbChunker(maxTokens: 500);
      final chunks = c.chunk('这是一个很短的文档。');
      expect(chunks.length, 1);
      expect(chunks.single.seq, 0);
      expect(chunks.single.text, contains('很短的文档'));
    });

    test('seq 连续递增', () {
      final c = KbChunker(maxTokens: 30);
      final chunks = c.chunk(List.generate(20, (i) => '第$i句内容。').join());
      expect(chunks.length, greaterThan(1));
      for (var i = 0; i < chunks.length; i++) {
        expect(chunks[i].seq, i);
      }
    });
  });

  group('预算约束', () {
    test('每块 token 数不超过 maxTokens(默认计数=字符数)', () {
      final c = KbChunker(maxTokens: 40);
      final src = '这是一段用于测试预算约束的中文文本。' * 30;
      final chunks = c.chunk(src);
      expect(chunks.length, greaterThan(1));
      for (final ch in chunks) {
        expect(c.countTokens(ch.text) <= 40, isTrue,
            reason: '块 ${ch.seq} 长度 ${ch.text.length} 超过预算');
      }
    });

    test('用**真分词器**量 token:不越 510 上限', () {
      final tokenizer = WordPieceTokenizer.fromJsonString(
        File('test/fixtures/bge_tokenizer.json').readAsStringSync(),
      );
      // 收满 500(字符)预算;再用真分词器复核实际 token 数。
      final c = KbChunker(maxTokens: 500);
      final src = List.generate(
        60,
        (i) => '第$i段:语音对话系统需要离线识别与合成能力,涉及声纹与克隆。',
      ).join('\n\n');
      final chunks = c.chunk(src);

      expect(chunks.length, greaterThan(1));
      for (final ch in chunks) {
        final contentTokens = tokenizer.encode(ch.text).inputIds.length - 2;
        expect(contentTokens, lessThanOrEqualTo(510),
            reason: '块 ${ch.seq} 实际 token=$contentTokens 超过模型上限 510');
      }
      expectFullCoverage(src, chunks);
    });
  });

  group('不丢内容(核心)', () {
    test('长文档:字符区间并集覆盖全部非空白字符', () {
      final c = KbChunker(maxTokens: 50);
      final src = List.generate(
        40,
        (i) => '这是第$i个句子的内容,用来把文档撑长。',
      ).join();
      final chunks = c.chunk(src);
      expect(chunks.length, greaterThan(3));
      expectFullCoverage(src, chunks);
    });

    test('多段落 + markdown 标题:仍全覆盖', () {
      final c = KbChunker(maxTokens: 60);
      final src = '''
# 第一章 概述

语音对话系统由离线识别、离线合成与声纹识别三部分组成。
它们各自独立加载,互不阻塞。

## 1.1 识别

使用 Paraformer 或 SenseVoice 模型。

## 1.2 合成

使用 VITS / Kokoro 家族的模型,支持中英混读。
''';
      final chunks = c.chunk(src);
      expect(chunks.length, greaterThan(1));
      expectFullCoverage(src, chunks);
    });

    test('无标点的超长段落:硬切且标记 hardSplit,内容不丢', () {
      final c = KbChunker(maxTokens: 20);
      final src = '甲' * 95; // 无任何句末标点
      final chunks = c.chunk(src);
      expect(chunks.length, greaterThan(1));
      expect(chunks.any((ch) => ch.hardSplit), isTrue,
          reason: '无标点超长段落应被标记为硬切,便于排查');
      expectFullCoverage(src, chunks);
    });

    test('每个块的区间都落在文档内:0 <= start < end <= 文档长度', () {
      // 这条曾经抓到过真实 bug:`_splitBlocks` 给最后一行补了一个源文本里不存在的
      // '\n',导致最后一块的 charEnd 比文档长度多 1。
      final c = KbChunker(maxTokens: 40);
      final src = '这是一句用来测试区间语义的内容。' * 20;
      final chunks = c.chunk(src);
      expect(chunks, isNotEmpty);
      for (final ch in chunks) {
        expect(ch.charStart >= 0, isTrue, reason: '块 ${ch.seq} 起点为负');
        expect(ch.charStart < ch.charEnd, isTrue,
            reason: '块 ${ch.seq} 区间为空或反向');
        expect(ch.charEnd <= src.length, isTrue,
            reason: '块 ${ch.seq} 终点 ${ch.charEnd} 越过文档长度 ${src.length}');
      }
    });

    test('无换行的单行长文档:区间不越界(off-by-one 回归)', () {
      final c = KbChunker(maxTokens: 16);
      final src = '甲' * 100; // 无标点、无换行
      final chunks = c.chunk(src);
      expect(chunks.length, greaterThan(1));
      for (final ch in chunks) {
        expect(ch.charEnd <= src.length, isTrue,
            reason: '块 ${ch.seq} 终点 ${ch.charEnd} 越过 ${src.length}');
      }
      expectFullCoverage(src, chunks);
    });

    test('行间换行符只写在两行之间(块文本不携带凭空多出的尾随换行)', () {
      final c = KbChunker(maxTokens: 500);
      final src = '第一行\n第二行';
      final chunks = c.chunk(src);
      expect(chunks.single.text, '第一行\n第二行');
      expect(chunks.single.text.endsWith('\n'), isFalse);
      expect(chunks.single.charEnd, src.length);
    });
  });

  group('换行风格(CRLF 常见于 Windows 编写的 .md)', () {
    test('CRLF 文档:区间不越界、内容全覆盖、且块文本里不留 \\r', () {
      final c = KbChunker(maxTokens: 30);
      final src = List.generate(
        12,
        (i) => '第$i段内容用于把文档撑长以便切分。',
      ).join('\r\n');
      final chunks = c.chunk(src);
      expect(chunks.length, greaterThan(1));
      for (final ch in chunks) {
        expect(ch.charEnd <= src.length, isTrue,
            reason: '块 ${ch.seq} 终点 ${ch.charEnd} 越过 ${src.length}');
        expect(ch.text.contains('\r'), isFalse,
            reason: '块 ${ch.seq} 文本里残留了 \\r');
      }
      expectFullCoverage(src, chunks);
    });

    test('CRLF 与 LF 切出相同的块数(换行风格不影响切块结果)', () {
      final lf = KbChunker(maxTokens: 30);
      final crlf = KbChunker(maxTokens: 30);
      final body = List.generate(12, (i) => '第$i段内容用于把文档撑长以便切分。');
      expect(
        crlf.chunk(body.join('\r\n')).length,
        lf.chunk(body.join('\n')).length,
      );
    });
  });

  group('语义边界', () {
    test('段落边界优先于句内切分:块边界落在段末', () {
      final c = KbChunker(maxTokens: 25);
      // 每段都很短,应尽量按段合并,而不是把段切开。
      final src = '第一段内容。\n\n第二段内容。\n\n第三段内容。\n\n第四段内容。';
      final chunks = c.chunk(src);
      for (final ch in chunks) {
        if (ch.hardSplit) continue;
        // 非硬切的块应以段落结束符或空白收尾,而不是半句话。
        expect(ch.text.trimRight().endsWith('。'), isTrue,
            reason: '块 ${ch.seq} 在句子中间断开:「${ch.text}」');
      }
    });

    test('相邻块存在重叠(长文档时)', () {
      final c = KbChunker(maxTokens: 60, overlapRatio: 0.2);
      final src = List.generate(
        30,
        (i) => '第$i句:这里放一些足够长的内容让它必须被切成多个块。',
      ).join();
      final chunks = c.chunk(src);
      expect(chunks.length, greaterThan(2));
      // 至少有一对相邻块共享内容(重叠)。
      var sawOverlap = false;
      for (var i = 1; i < chunks.length; i++) {
        final prev = chunks[i - 1].text;
        final cur = chunks[i].text;
        // 取前一块尾部 8 个字符,看是否出现在当前块开头部分。
        final probe = prev.substring((prev.length - 8).clamp(0, prev.length));
        if (probe.isNotEmpty && cur.contains(probe)) {
          sawOverlap = true;
          break;
        }
      }
      expect(sawOverlap, isTrue, reason: '未观察到相邻块重叠');
    });

    test('overlapRatio=0 时不加重叠', () {
      final c = KbChunker(maxTokens: 60, overlapRatio: 0);
      final src = List.generate(20, (i) => '第$i句内容足够长以便触发切分。').join();
      final chunks = c.chunk(src);
      expect(chunks.length, greaterThan(1));
      // 前一块尾部不应出现在后一块里(无重叠)。
      for (var i = 1; i < chunks.length; i++) {
        final prev = chunks[i - 1].text;
        final cur = chunks[i].text;
        if (prev.length < 10) continue;
        final probe = prev.substring(prev.length - 10);
        expect(cur.startsWith(probe), isFalse);
      }
    });

    test('重叠也受预算约束,不会把块顶超 maxTokens', () {
      final c = KbChunker(maxTokens: 40, overlapRatio: 0.5);
      final src = List.generate(30, (i) => '第$i句内容用于把文档撑得足够长。').join();
      final chunks = c.chunk(src);
      for (final ch in chunks) {
        expect(c.countTokens(ch.text) <= 40, isTrue,
            reason: '块 ${ch.seq} 因重叠超预算:${c.countTokens(ch.text)}');
      }
    });
  });

  group('与 TextChunker 的分工(防误用)', () {
    test('切块粒度明显不同于 TTS 分块:知识块应远大于 TTS 短语', () {
      // TTS 的 TextChunker 目标是"整句 ≤20 词",知识库切块目标是"尽量装满预算"。
      // 若有人把两者互换,这条会失败。
      final kb = KbChunker(maxTokens: 500);
      final src = List.generate(20, (i) => '第$i句比较长的一段中文内容,用于对比粒度。').join();
      final chunks = kb.chunk(src);
      // 20 句总长约 400 字,应被切成很少的块(而非每句一块)。
      expect(chunks.length, lessThanOrEqualTo(2),
          reason: '知识库切块过碎,疑似误用了 TTS 的切块策略');
    });
  });
}
