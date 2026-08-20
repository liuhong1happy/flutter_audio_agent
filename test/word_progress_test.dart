/// 验证"逐词高亮"随时间推进(currentWordIndex 递增)。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tts_demo/app_dependencies.dart';
import 'package:flutter_tts_demo/data/archive_extractor.dart';
import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/tts/text_chunker.dart';

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

    await deps.streamingService.speak('今天天气不错。');
    expect(deps.streamingService.segments, isNotEmpty);
    expect(deps.streamingService.utterances, hasLength(1));

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
}
