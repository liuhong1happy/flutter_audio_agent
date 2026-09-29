/// 验证"逐词高亮"随时间推进(currentWordIndex 递增)。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tts_demo/data/app_dependencies.dart';
import 'package:flutter_tts_demo/data/archive_extractor.dart';
import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/utils/text_chunker.dart';
import 'package:flutter_tts_demo/utils/tts_streaming_service.dart';

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
      appLock: FakeAppLockService(),
      engine: FakeTtsEngine(segmentDuration: const Duration(milliseconds: 200)),
      downloader: FakeModelDownloader(),
      chunker: TextChunker(enableJieba: false),
      extractor: const ArchiveExtractor(useCompute: false),
      player: playback,
      micRecorder: FakeMicRecorder(),
      conversationPlayer: FakeAudioPlaybackQueue(),
      conversationStore: MemoryConversationStore(),
      modelsDirProvider: () async => Directory('${tempDir.path}/models'),
      audioCacheDirProvider: () async => Directory('${tempDir.path}/audio'),
      cloneRefsDirProvider: () async => Directory('${tempDir.path}/clone_refs'),
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
    final firstRealWords = deps.streamingService.utterances.last.segmentWords.first
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
      appLock: FakeAppLockService(),
      engine: FakeTtsEngine(segmentDuration: const Duration(milliseconds: 100)),
      downloader: FakeModelDownloader(),
      chunker: TextChunker(enableJieba: false),
      extractor: const ArchiveExtractor(useCompute: false),
      player: FakeAudioPlaybackQueue(
        delayPerSegment: const Duration(milliseconds: 150),
      ),
      micRecorder: FakeMicRecorder(),
      conversationPlayer: FakeAudioPlaybackQueue(),
      conversationStore: MemoryConversationStore(),
      modelsDirProvider: () async => Directory('${tempDir.path}/models'),
      audioCacheDirProvider: () async => Directory('${tempDir.path}/audio'),
      cloneRefsDirProvider: () async => Directory('${tempDir.path}/clone_refs'),
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

  test('分块策略:首句1+4+10,后续句整句,长句按10切', () async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = Directory.systemTemp.createTempSync('chunk_');

    final deps = AppDependencies(
      appLock: FakeAppLockService(),
      engine: FakeTtsEngine(segmentDuration: const Duration(milliseconds: 20)),
      downloader: FakeModelDownloader(),
      chunker: TextChunker(enableJieba: false),
      extractor: const ArchiveExtractor(useCompute: false),
      player: FakeAudioPlaybackQueue(
        delayPerSegment: const Duration(milliseconds: 50),
      ),
      micRecorder: FakeMicRecorder(),
      conversationPlayer: FakeAudioPlaybackQueue(),
      conversationStore: MemoryConversationStore(),
      modelsDirProvider: () async => Directory('${tempDir.path}/models'),
      audioCacheDirProvider: () async => Directory('${tempDir.path}/audio'),
      cloneRefsDirProvider: () async => Directory('${tempDir.path}/clone_refs'),
    );
    await deps.init();
    final model = ModelCatalog.all.first;
    await deps.modelManager.downloadModel(model);
    await deps.settings.selectModel(model.id);

    // 场景1:首句(3词)→ 渐进 [1, 剩余2];第二句(1词)→ 整句 1 块。共 3 块。
    await deps.streamingService.speak('你好 world 你好。今天天气不错。');
    final segs1 = deps.streamingService.segments;
    expect(segs1, hasLength(3), reason: '首句2块 + 第二句整句1块');
    expect(
      deps.streamingService.utterances.last.segmentWords.first
          .where((w) => !w.isSeparator)
          .length,
      1,
      reason: '首句首块应只有 1 个词(最快出声)',
    );

    // 场景2:首句 11 个英文词 → 1 + 4 + 6 = 3 块。
    await deps.streamingService.speak('a b c d e f g h i j k。');
    final segs2 = deps.streamingService.segments;
    expect(segs2, hasLength(3), reason: '首句 11 词按 1+4+剩余6 切成 3 块');

    await deps.streamingService.disposeAll();
    tempDir.deleteSync(recursive: true);
  });

  test('分块:按中英文逗号切句,块落在自然短语边界', () async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = Directory.systemTemp.createTempSync('comma_');

    final deps = AppDependencies(
      appLock: FakeAppLockService(),
      engine: FakeTtsEngine(segmentDuration: Duration.zero),
      downloader: FakeModelDownloader(),
      chunker: TextChunker(enableJieba: false),
      extractor: const ArchiveExtractor(useCompute: false),
      player: FakeAudioPlaybackQueue(),
      micRecorder: FakeMicRecorder(),
      conversationPlayer: FakeAudioPlaybackQueue(),
      conversationStore: MemoryConversationStore(),
      modelsDirProvider: () async => Directory('${tempDir.path}/models'),
      audioCacheDirProvider: () async => Directory('${tempDir.path}/audio'),
      cloneRefsDirProvider: () async => Directory('${tempDir.path}/clone_refs'),
    );
    await deps.init();
    final model = ModelCatalog.all.first;
    await deps.modelManager.downloadModel(model);
    await deps.settings.selectModel(model.id);

    // 中文逗号:3 个短语 → 3 块,块尾即逗号/句号(不跨逗号)。
    await deps.streamingService.speak('今天天气不错,我们一起去公园玩,顺便吃饭。');
    final segs1 = deps.streamingService.segments;
    expect(segs1, hasLength(3), reason: '应按中文逗号切成 3 个短语块');
    expect(segs1.map((s) => s.text).join(),
        deps.streamingService.normalization!.text,
        reason: '拼接应完整覆盖全文');
    expect(segs1[0].text.endsWith(','), isTrue);
    expect(segs1[1].text.endsWith(','), isTrue);
    expect(segs1[2].text.endsWith('。'), isTrue);

    // 英文逗号同理。
    await deps.streamingService.speak('Hello, world, bye.');
    final segs2 = deps.streamingService.segments;
    expect(segs2, hasLength(3), reason: '应按英文逗号切成 3 块');
    expect(segs2[0].text.trim(), 'Hello,');

    await deps.streamingService.disposeAll();
    tempDir.deleteSync(recursive: true);
  });

  test('分块改进:句首引号保留 / 换行不产生空块 / ≤20词长句整句', () async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = Directory.systemTemp.createTempSync('chunk_fix_');

    final deps = AppDependencies(
      appLock: FakeAppLockService(),
      engine: FakeTtsEngine(segmentDuration: Duration.zero),
      downloader: FakeModelDownloader(),
      chunker: TextChunker(enableJieba: false),
      extractor: const ArchiveExtractor(useCompute: false),
      player: FakeAudioPlaybackQueue(),
      micRecorder: FakeMicRecorder(),
      conversationPlayer: FakeAudioPlaybackQueue(),
      conversationStore: MemoryConversationStore(),
      modelsDirProvider: () async => Directory('${tempDir.path}/models'),
      audioCacheDirProvider: () async => Directory('${tempDir.path}/audio'),
      cloneRefsDirProvider: () async => Directory('${tempDir.path}/clone_refs'),
    );
    await deps.init();
    final model = ModelCatalog.all.first;
    await deps.modelManager.downloadModel(model);
    await deps.settings.selectModel(model.id);

    // 句首引号保留 + 段落换行合并(不产生空块)。
    await deps.streamingService.speak('“用新技术改造提升传统产业”。\n\n第二段,继续。');
    final s1 = deps.streamingService.segments;
    expect(s1.first.text.startsWith('“用'), isTrue, reason: '首块应保留句首引号');
    expect(s1.any((s) => s.text.trim().isEmpty), isFalse,
        reason: '段落换行应并入前块,不产生空块');
    expect(s1.map((s) => s.text).join(),
        deps.streamingService.normalization!.text,
        reason: '段应完整覆盖原文');

    // 顿号分割:含顿号的长句被切成短语块,块尾带顿号。
    await deps.streamingService.speak('内容涵盖了青春励志、情感故事、社会热点等多个方面,注重深度。');
    final sDun = deps.streamingService.segments;
    expect(sDun.any((s) => s.text.endsWith('、')), isTrue,
        reason: '顿号应是分块边界(块尾带顿号)');
    expect(sDun.map((s) => s.text).join(),
        deps.streamingService.normalization!.text);
    final longestDun = sDun.fold<int>(0, (m, s) => s.text.length > m ? s.text.length : m);
    expect(longestDun, lessThan(25), reason: '顿号切分后不应出现超长块');

    // 年月日整块:日期不被首句渐进拆散。
    await deps.streamingService.speak('2026 年 08 月 21 日,实验室完成版本迭代。');
    final sDate = deps.streamingService.segments;
    expect(sDate.first.text.contains('年') && sDate.first.text.contains('月') &&
            sDate.first.text.contains('日'),
        isTrue,
        reason: '年月日应在一个块内');
    expect(sDate.map((s) => s.text).join(),
        deps.streamingService.normalization!.text);

    // 后续句 11 词(≤16)应整句一块,不再切成 10+1。
    await deps.streamingService.speak('你好。a b c d e f g h i j k,继续。');
    final s2 = deps.streamingService.segments;
    final longClause =
        s2.where((s) => s.text.trim().startsWith('a ')).toList();
    expect(longClause, hasLength(1), reason: '11 词后续句应整句一块');
    expect(longClause.first.text.trim(), 'a b c d e f g h i j k,');

    await deps.streamingService.disposeAll();
    tempDir.deleteSync(recursive: true);
  });

  test('历史恢复的气泡(segments 为空)重读时重新分块并播放', () async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = Directory.systemTemp.createTempSync('history_replay_');

    final playback = FakeAudioPlaybackQueue(
      delayPerSegment: const Duration(milliseconds: 30),
    );
    final engine = FakeTtsEngine(segmentDuration: const Duration(milliseconds: 5));
    final deps = AppDependencies(
      appLock: FakeAppLockService(),
      engine: engine,
      downloader: FakeModelDownloader(),
      chunker: TextChunker(enableJieba: false),
      extractor: const ArchiveExtractor(useCompute: false),
      player: playback,
      micRecorder: FakeMicRecorder(),
      conversationPlayer: FakeAudioPlaybackQueue(),
      conversationStore: MemoryConversationStore(),
      modelsDirProvider: () async => Directory('${tempDir.path}/models'),
      audioCacheDirProvider: () async => Directory('${tempDir.path}/audio'),
      cloneRefsDirProvider: () async => Directory('${tempDir.path}/clone_refs'),
    );
    await deps.init();
    final model = ModelCatalog.all.first;
    await deps.modelManager.downloadModel(model);
    await deps.settings.selectModel(model.id);

    await deps.streamingService.speak('你好 world 你好。今天天气不错。');
    final u = deps.streamingService.utterances.last;
    expect(u.segments, isNotEmpty, reason: '首次朗读应产生分块');
    final generatedBefore = engine.generatedTexts.length;

    // 模拟历史恢复:segments / words 被清空(loadHistory 只存原文+统计)。
    u.segments = [];
    u.segmentWords = [];
    u.allWords = [];
    u.normalization = null;
    expect(u.segments, isEmpty, reason: '前提:历史恢复后分块为空');

    await deps.streamingService.replayUtterance(0);
    expect(u.segments, isNotEmpty, reason: '重读时应重新分块');

    // 等待播放推进(合成是异步拉取)。
    for (var i = 0;
        i < 30 && playback.startedSegmentIndexes.isEmpty;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(playback.startedSegmentIndexes, isNotEmpty,
        reason: '重读应有段开始播放');
    expect(engine.generatedTexts.length, greaterThan(generatedBefore),
        reason: '重读应重新走合成');

    await deps.streamingService.disposeAll();
    tempDir.deleteSync(recursive: true);
  });
}
