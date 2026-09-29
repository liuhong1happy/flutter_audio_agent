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
      appLock: FakeAppLockService(),
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

  testWidgets('文本模式零模型可用:只需配置大模型,不给模型下载入口', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = Directory.systemTemp.createTempSync('conv_text_');
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
    await tester.runAsync(() async => deps.init());

    await tester.pumpWidget(TtsDemoApp(dependencies: deps));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tabConversation')));
    await tester.pumpAndSettle();

    // 音频模式 + 零模型:显示三件套下载,并提示还缺大模型。
    expect(find.byKey(const ValueKey('initDownloadButton')), findsOneWidget);
    expect(find.byKey(const ValueKey('configureLlmButton')), findsOneWidget);

    // 切到文本模式(按图标点,不依赖语言):**不下载任何模型**,只显示"配置大模型"。
    await tester.tap(find.byIcon(Icons.chat_outlined));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('initDownloadButton')), findsNothing,
        reason: '文本模式不该给模型下载入口');
    expect(find.byKey(const ValueKey('configureLlmButton')), findsOneWidget);
    expect(find.byKey(const ValueKey('sendTextButton')), findsNothing);

    // 只填 API Key → 文本模式直接放行,连一个本地模型都没下。
    await tester.runAsync(() async => deps.settings.setLlmApiKey('k'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sendTextButton')), findsOneWidget);
    expect(find.byKey(const ValueKey('initDownloadButton')), findsNothing);
    expect(find.byKey(const ValueKey('configureLlmButton')), findsNothing);

    await tester.runAsync(() async {
      deps.conversationService.dispose();
      await deps.streamingService.disposeAll();
      tempDir.deleteSync(recursive: true);
    });
  });
}
