/// 历史浏览页测试:左上角入口 + 向前翻页(加载更早)。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tts_demo/app.dart';
import 'package:flutter_tts_demo/data/app_dependencies.dart';
import 'package:flutter_tts_demo/data/models/conversation_message.dart';
import 'package:flutter_tts_demo/data/archive_extractor.dart';
import 'package:flutter_tts_demo/utils/text_chunker.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('历史页:左上角入口 → 加载更早分页', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final tempDir = Directory.systemTemp.createTempSync('history_');

    // 预置 60 条历史,使 loadHistory 后 hasMore=true(一页 50)。
    final store = MemoryConversationStore();
    for (var i = 1; i <= 60; i++) {
      await store.insert(ConversationMessage(
        role: i.isOdd ? ConversationRole.user : ConversationRole.assistant,
        content: 'm$i',
        speakerName: i.isOdd ? '张三' : null,
        createdAt: i,
      ));
    }

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
      conversationStore: store,
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

    // 左上角历史入口。
    await tester.tap(find.byKey(const ValueKey('historyButton')));
    await tester.pumpAndSettle();

    // 有更多历史 → 显示"加载更早"。
    expect(find.byKey(const ValueKey('loadOlderButton')), findsOneWidget);

    // 点"加载更早"后,更早的历史加载完,按钮消失(hasMore=false)。
    await tester.tap(find.byKey(const ValueKey('loadOlderButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('loadOlderButton')), findsNothing);

    await tester.runAsync(() async {
      deps.conversationService.dispose();
      await deps.streamingService.disposeAll();
      tempDir.deleteSync(recursive: true);
    });
  });
}
