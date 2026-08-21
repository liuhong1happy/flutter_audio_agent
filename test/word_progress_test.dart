/// 验证"逐词高亮"随时间推进(currentWordIndex 递增)。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tts_demo/app_dependencies.dart';
import 'package:flutter_tts_demo/data/archive_extractor.dart';
import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/tts/text_chunker.dart';
import 'package:flutter_tts_demo/tts/tts_streaming_service.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('播放时 currentWordIndex 随时间推进', () async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = Directory.systemTemp.createTempSync('word_progress_');

    final playback = FakeAudioPlaybackQueue(
      delayPerSegment: const Duration(milliseconds: 400),
    );
    final deps = AppDependencies(
      engine: FakeTtsEngine(segmentDuration: const Duration(milliseconds: 200)),
      downloader: FakeModelDownloader(),
      chunker: TextChunker(enableJieba: false),
      extractor: const ArchiveExtractor(useCompute: false),
      player: playback,
      modelsDirProvider: () async => Directory('${tempDir.path}/models'),
      audioCacheDirProvider: () async => Directory('${tempDir.path}/audio'),
    );
    await deps.init();

    final model = ModelCatalog.all.first;
    await deps.modelManager.downloadModel(model);
    await deps.settings.selectModel(model.id);

    // 中英混合:无 jieba 也能分出多个词,验证渐进分块下词高亮推进。
    await deps.streamingService.speak('你好 world 你好。');
    expect(deps.streamingService.segments, isNotEmpty);
    expect(deps.streamingService.utterances, hasLength(1));

    // 渐进分块不变式:所有块拼回 == 归一化全文;首块词最少(快速出声)。
    final joined = deps.streamingService.segments.map((s) => s.text).join();
    expect(joined, deps.streamingService.normalization!.text,
        reason: '渐进分块应完整覆盖全文');
    final firstRealWords = deps.streamingService.segmentWords.first
        .where((w) => !w.isSeparator)
        .length;
    expect(firstRealWords, 1, reason: '首块应只有 1 个词,保证最快出声');

    // 等待第一段开始播放并让词计时器推进。
    final seen = <int>{};
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final w = deps.streamingService.currentWordIndex;
      if (w >= 0) seen.add(w);
    }
    // 诊断:播放器是否真的开始播放了段。
    // ignore: avoid_print
    print('phase=${deps.streamingService.phase} '
        'startedSegments=${playback.startedSegmentIndexes} '
        'currentWord=$seen');
    expect(seen, isNotEmpty, reason: '应有词高亮');
    expect(seen.length, greaterThan(1), reason: '词高亮应随时间推进(不止一个词)');

    await deps.streamingService.disposeAll();
    tempDir.deleteSync(recursive: true);
  });

  test('气泡耗时统计:分词/首词/合成/音频/总时长均被记录,持久化为毫秒', () async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = Directory.systemTemp.createTempSync('stats_');

    final deps = AppDependencies(
      engine: FakeTtsEngine(segmentDuration: const Duration(milliseconds: 100)),
      downloader: FakeModelDownloader(),
      chunker: TextChunker(enableJieba: false),
      extractor: const ArchiveExtractor(useCompute: false),
      player: FakeAudioPlaybackQueue(
        delayPerSegment: const Duration(milliseconds: 150),
      ),
      modelsDirProvider: () async => Directory('${tempDir.path}/models'),
      audioCacheDirProvider: () async => Directory('${tempDir.path}/audio'),
    );
    await deps.init();

    final model = ModelCatalog.all.first;
    await deps.modelManager.downloadModel(model);
    await deps.settings.selectModel(model.id);

    await deps.streamingService.speak('你好 world 你好。');
    // 等待播放完成(统计写入)。
    for (var i = 0;
        i < 40 && deps.streamingService.phase != StreamingPhase.finished;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    final s = deps.streamingService.utterances.last.stats;
    expect(s.tokenizeTime, greaterThan(Duration.zero), reason: '分词时间 > 0');
    expect(s.firstAudioLatency, greaterThan(Duration.zero),
        reason: '首词返回时间 > 0');
    expect(s.synthesisTotal, greaterThan(Duration.zero),
        reason: '文本转音频总时长 > 0');
    expect(s.audioDuration, greaterThan(Duration.zero),
        reason: '音频播放时长 > 0');
    expect(s.processingTotal, greaterThan(Duration.zero),
        reason: '总处理时长 > 0');

    // 毫秒级持久化往返一致。
    final json = s.toJson();
    final s2 = UtteranceStats();
    s2.fromJson(json);
    expect(s2.toJson(), json, reason: '毫秒级持久化往返应一致');

    await deps.streamingService.disposeAll();
    tempDir.deleteSync(recursive: true);
  });
}
