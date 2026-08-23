/// 对话端到端集成测试(全假):音频模式(语音 → LLM → TTS 回复)+
/// 文本模式(打字 → LLM → 纯文本回复)。
///
/// 运行方式(需已连接 Android 设备/模拟器):
///   patrol test -t patrol_test/conversation_test.dart
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_tts_demo/app.dart';
import 'package:flutter_tts_demo/data/app_dependencies.dart';
import 'package:flutter_tts_demo/data/archive_extractor.dart';
import 'package:flutter_tts_demo/utils/text_chunker.dart';
import 'package:patrol/patrol.dart';

import '../test/support/fakes.dart';
import 'screenshot_helper.dart';

void main() {
  patrolTest('对话:音频模式语音回复 + 文本模式打字回复', ($) async {
    final tempDir = Directory.systemTemp.createTempSync('patrol_conv_');
    final vad = FakeVadEngine();
    final asr = FakeAsrEngine()..nextText = '你好';
    final llm = FakeLlmClient(chunks: ['你好,', '我是语音助手']);

    final deps = AppDependencies(
      engine: FakeTtsEngine(segmentDuration: const Duration(milliseconds: 300)),
      downloader: FakeModelDownloader(),
      chunker: TextChunker(enableJieba: false),
      extractor: const ArchiveExtractor(useCompute: false),
      player: FakeAudioPlaybackQueue(
        delayPerSegment: const Duration(milliseconds: 300),
      ),
      conversationPlayer: FakeAudioPlaybackQueue(
        delayPerSegment: const Duration(milliseconds: 300),
      ),
      conversationStore: MemoryConversationStore(),
      micRecorder: FakeMicRecorder(),
      vadEngine: vad,
      asrEngine: asr,
      speakerEngine: FakeSpeakerEngine(),
      pocketEngine: FakePocketTtsEngine(),
      llmClient: llm,
      modelsDirProvider: () async => Directory('${tempDir.path}/models'),
      audioCacheDirProvider: () async => Directory('${tempDir.path}/audio'),
      cloneRefsDirProvider: () async => Directory('${tempDir.path}/clone_refs'),
    );
    await deps.init();
    await deps.conversationService.downloadInitialModels(null);
    await deps.settings.setLlmApiKey('k');

    await $.pumpWidgetAndSettle(
      RepaintBoundary(
        key: screenshotBoundaryKey,
        child: TtsDemoApp(dependencies: deps),
      ),
    );

    // ── 音频模式 ──────────────────────────────────────────────────
    await $(#tabConversation).tap();
    await $.pumpAndSettle();
    await takeScreenshot($.tester, '01_audio_ready');

    await $(#conversationToggleButton).tap();
    await $.pumpAndSettle();
    await takeScreenshot($.tester, '02_listening');

    vad.emitSegment(Float32List(160));
    await $(RegExp('你好,我是语音助手'))
        .waitUntilVisible(timeout: const Duration(seconds: 15));
    await takeScreenshot($.tester, '03_audio_reply');

    // 停止语音对话。
    await $(#conversationToggleButton).tap();
    await $.pumpAndSettle();

    // ── 文本模式 ──────────────────────────────────────────────────
    await $(RegExp('Text')).tap();
    await $.pumpAndSettle();
    await takeScreenshot($.tester, '04_text_mode');

    llm.chunks
      ..clear()
      ..addAll(['好的,已收到你的消息']);
    await $(#textInput).enterText('帮我查一下天气');
    await $(#sendTextButton).tap();
    await $(RegExp('好的,已收到你的消息'))
        .waitUntilVisible(timeout: const Duration(seconds: 15));
    await takeScreenshot($.tester, '05_text_reply');

    deps.conversationService.dispose();
    await deps.streamingService.disposeAll();
  });
}
