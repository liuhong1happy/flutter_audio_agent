/// 对话页 widget 测试(全假):未就绪显示初始化卡片,就绪显示开始按钮。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tts_demo/app.dart';
import 'package:flutter_tts_demo/data/app_dependencies.dart';
import 'package:flutter_tts_demo/data/archive_extractor.dart';
import 'package:flutter_tts_demo/utils/text_chunker.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('对话页:未就绪 → 一键下载 → 就绪显示开始对话', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = Directory.systemTemp.createTempSync('conv_page_');

    final deps = AppDependencies(
      engine: FakeTtsEngine(segmentDuration: Duration.zero),
      downloader: FakeModelDownloader(),
      chunker: TextChunker(enableJieba: false),
      extractor: const ArchiveExtractor(useCompute: false),
      player: FakeAudioPlaybackQueue(),
      micRecorder: FakeMicRecorder(),
      vadEngine: FakeVadEngine(),
      asrEngine: FakeAsrEngine(),
      speakerEngine: FakeSpeakerEngine(),
      pocketEngine: FakePocketTtsEngine(),
      llmClient: FakeLlmClient(),
      conversationPlayer: FakeAudioPlaybackQueue(),
      conversationStore: MemoryConversationStore(),
      modelsDirProvider: () async => Directory('${tempDir.path}/models'),
      audioCacheDirProvider: () async => Directory('${tempDir.path}/audio'),
      cloneRefsDirProvider: () async => Directory('${tempDir.path}/clone_refs'),
    );
    await tester.runAsync(() async => deps.init());

    await tester.pumpWidget(TtsDemoApp(dependencies: deps));
    await tester.pumpAndSettle();

    // 切到对话 Tab。
    await tester.tap(find.byKey(const ValueKey('tabConversation')));
    await tester.pumpAndSettle();

    // 未就绪:显示初始化卡片与一键下载按钮。
    expect(find.byKey(const ValueKey('initDownloadButton')), findsOneWidget);
    expect(find.byKey(const ValueKey('conversationToggleButton')), findsNothing);

    // 一键下载(真实文件 I/O 在 runAsync 内)。
    await tester.runAsync(() async {
      await deps.conversationService.downloadInitialModels(null);
      await deps.settings.setLlmApiKey('k');
    });
    await tester.pumpAndSettle();

    // 就绪:显示开始对话按钮,初始化卡片消失。
    expect(find.byKey(const ValueKey('conversationToggleButton')), findsOneWidget);
    expect(find.byKey(const ValueKey('initDownloadButton')), findsNothing);

    await tester.runAsync(() async {
      deps.conversationService.dispose();
      await deps.streamingService.disposeAll();
      tempDir.deleteSync(recursive: true);
    });
  });
}
