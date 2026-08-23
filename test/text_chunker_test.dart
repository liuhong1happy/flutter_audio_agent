import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts_demo/utils/text_chunker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TextChunker 分句', () {
    test('按句末标点切句', () {
      final c = TextChunker();
      final segs = c.chunk('你好。这是一个测试！');
      expect(segs, hasLength(2));
      expect(segs[0].text, '你好。');
      expect(segs[1].text, '这是一个测试！');
      // 偏移连续:"你好。" 3 字符。
      expect(segs[0].end, 3);
      expect(segs[1].start, 3);
    });

    test('无标点时整段一个片段', () {
      final c = TextChunker();
      final segs = c.chunk('今天天气不错');
      expect(segs, hasLength(1));
      expect(segs.first.text, '今天天气不错');
    });

    test('过短句与前一句合并', () {
      final c = TextChunker(minSegmentLen: 6);
      // 尾句 "嗯。" 2 字 < 6,合并到前一句。
      final segs = c.chunk('今天天气真不错啊。嗯。');
      expect(segs, hasLength(1));
      expect(segs.first.text, '今天天气真不错啊。嗯。');
    });
  });

  group('TextChunker 长句 jieba 切块', () {
    test('超长句被切成不超过上限的片段且拼接回原文', () async {
      final c = TextChunker(maxSegmentLen: 20, minSegmentLen: 1);
      await c.ensureInitialized();
      expect(c.jiebaReady, isTrue);

      final longText = '今天是二零二四年六月十五日,阳光明媚,微风拂面。'
          '我在公园里散步,看到许多小朋友在放风筝,他们玩得特别开心。'
          '远处的小河静静地流淌,河边的柳树随风摇曳,景色非常优美。';
      final segs = c.chunk(longText);
      expect(segs, isNotEmpty);
      for (final s in segs) {
        expect(s.length, lessThanOrEqualTo(20));
      }
      // 拼接等于原文。
      final joined = segs.map((s) => s.text).join();
      expect(joined, longText);
    });
  });
}
