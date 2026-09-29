/// 应用冒烟测试:用假引擎/假下载器/假播放器在测试环境中跑通
/// "输入文本 → 归一化 → 分句 → 合成 → 朗读视图高亮推进"链路。
///
/// 注意:所有涉及真实文件 I/O 的 setup(下载/解压)必须包在
/// `tester.runAsync` 中执行,否则 fake-async 区内 I/O 永不完成。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tts_demo/app.dart';
import 'package:flutter_tts_demo/data/app_dependencies.dart';
import 'package:flutter_tts_demo/data/archive_extractor.dart';
import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/utils/text_chunker.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('输入文本合成后朗读视图展示归一化片段并推进高亮', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = Directory.systemTemp.createTempSync('tts_smoke_');

    final engine = FakeTtsEngine(segmentDuration: Duration.zero);
    final playback = FakeAudioPlaybackQueue();
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

    // 真实文件 I/O(下载 tar.bz2 → 解压)须在 runAsync 中执行。
    await tester.runAsync(() async {
      await deps.init();
      final defaultModel = ModelCatalog.all.first;
      await deps.modelManager.downloadModel(defaultModel);
      await deps.settings.selectModel(defaultModel.id);
    });
    final defaultModel = ModelCatalog.all.first;
    expect(deps.modelManager.isDownloaded(defaultModel.id), isTrue);

    await tester.pumpWidget(TtsDemoApp(dependencies: deps));
    await tester.pumpAndSettle();

    // 输入文本并点击合成。
    await tester.enterText(
      find.byKey(const ValueKey('ttsInput')),
      '价格12.5元。拨打110求助。',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('speakButton')));
    await tester.pump();

    // 等待合成管线推进。
    for (var i = 0; i < 30 && playback.startedSegmentIndexes.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(engine.generatedTexts, isNotEmpty,
        reason: '引擎应收到至少一段合成请求');
    expect(playback.startedSegmentIndexes, isNotEmpty,
        reason: '应至少开始播放一段(朗读进度高亮推进)');

    // 发送成功后输入框应清空。
    final input = tester.widget<TextField>(
      find.byKey(const ValueKey('ttsInput')),
    );
    expect(input.controller?.text, isEmpty,
        reason: '发送后输入框应清空');

    // 归一化文本应出现在朗读视图中。
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('价格十二点五元'), findsOneWidget);

    await tester.runAsync(() async {
      await deps.streamingService.disposeAll();
      tempDir.deleteSync(recursive: true);
    });
  });
}
