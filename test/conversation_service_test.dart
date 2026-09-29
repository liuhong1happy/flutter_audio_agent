/// 对话编排服务测试(全假):初始化/就绪判定、VAD 段驱动状态迁移、
/// 访客模式、声纹识别说话人路由与按人历史。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tts_demo/data/app_dependencies.dart';
import 'package:flutter_tts_demo/data/models/conversation_message.dart';
import 'package:flutter_tts_demo/utils/conversation_service.dart';
import 'package:flutter_tts_demo/data/archive_extractor.dart';
import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/utils/text_chunker.dart';

import 'support/fakes.dart';

Future<AppDependencies> _deps({
  FakeAsrEngine? asr,
  FakeSpeakerEngine? speaker,
  FakeVadEngine? vad,
  FakeLlmClient? llm,
  FakeMicRecorder? mic,
  MemoryConversationStore? store,
}) async {
  SharedPreferences.setMockInitialValues({});
  final tempDir = Directory.systemTemp.createTempSync('conv_');
  final deps = AppDependencies(
    appLock: FakeAppLockService(),
    engine: FakeTtsEngine(segmentDuration: Duration.zero),
    downloader: FakeModelDownloader(),
    chunker: TextChunker(enableJieba: false),
    extractor: const ArchiveExtractor(useCompute: false),
    player: FakeAudioPlaybackQueue(delayPerSegment: Duration.zero),
    conversationPlayer: FakeAudioPlaybackQueue(delayPerSegment: Duration.zero),
    conversationStore: store ?? MemoryConversationStore(),
    micRecorder: mic ?? FakeMicRecorder(),
    vadEngine: vad ?? FakeVadEngine(),
    asrEngine: asr ?? FakeAsrEngine(),
    speakerEngine: speaker ?? FakeSpeakerEngine(),
    pocketEngine: FakePocketTtsEngine(),
    llmClient: llm ?? FakeLlmClient(),
    modelsDirProvider: () async => Directory('${tempDir.path}/models'),
    audioCacheDirProvider: () async => Directory('${tempDir.path}/audio'),
    cloneRefsDirProvider: () async => Directory('${tempDir.path}/clone_refs'),
  );
  await deps.init();
  addTearDown(() async {
    await deps.streamingService.disposeAll();
    deps.conversationService.dispose();
    tempDir.deleteSync(recursive: true);
  });
  return deps;
}

Future<void> _waitFor(
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('等待超时');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('一键初始化:配置默认 ASR + 发音,就绪状态变 true', () async {
    final deps = await _deps();
    expect(deps.conversationService.isReadyForConversation, isFalse);

    await deps.conversationService.downloadInitialModels(null);

    expect(deps.settings.asrModelId, kDefaultConversationModelIds['asr']);
    expect(
      deps.settings.conversationModelVoiceId,
      kDefaultConversationModelIds['tts'],
    );
    expect(deps.conversationService.isReadyForConversation, isTrue);
  });

  test('就绪判定按模式区分:文本模式只用大模型,一个本地模型都不需要', () async {
    final deps = await _deps();
    final svc = deps.conversationService;

    // 什么都没配:两种模式都不就绪。
    expect(svc.isReadyForTextMode, isFalse);
    expect(svc.isReadyForAudioMode, isFalse);

    // 只配大模型 → 文本模式立刻可用,音频模式仍不行(缺三件套)。
    await deps.settings.setLlmApiKey('k');
    expect(svc.isReadyForTextMode, isTrue);
    expect(svc.isReadyForAudioMode, isFalse);
    expect(svc.isReadyForConversation, isFalse, reason: '三件套仍未就绪');

    // 补齐三件套 → 音频模式也就绪。
    await svc.downloadInitialModels(null);
    expect(svc.isReadyForAudioMode, isTrue);
    expect(svc.isReadyForConversation, isTrue);
  });

  test('三件套齐但未配大模型:音频模式不就绪(两种模式都需要大模型)', () async {
    final deps = await _deps();
    await deps.conversationService.downloadInitialModels(null);

    expect(deps.conversationService.isReadyForConversation, isTrue,
        reason: '模型维度已就绪');
    expect(deps.conversationService.isReadyForAudioMode, isFalse,
        reason: '音频模式还要求大模型');
    expect(deps.conversationService.isReadyForTextMode, isFalse);

    await deps.settings.setLlmApiKey('k');
    expect(deps.conversationService.isReadyForAudioMode, isTrue);
  });

  test('文本模式零模型也能跑通 sendText', () async {
    final llm = FakeLlmClient(chunks: ['文本回复']);
    final deps = await _deps(llm: llm);

    // 刻意不下载任何模型。
    await deps.settings.setLlmApiKey('k');
    expect(deps.conversationService.isReadyForTextMode, isTrue);

    await deps.conversationService.sendText('你好');
    await _waitFor(
      () => deps.conversationService.phase == ConversationPhase.idle,
    );

    expect(llm.capturedMessages, isNotEmpty);
    final fakeEngine = deps.engine as FakeTtsEngine;
    expect(fakeEngine.generatedTexts, isEmpty, reason: '文本模式不转 TTS');
  });

  test('VAD 段驱动访客对话:转写 → LLM → 回复消息(访客不泄身份)', () async {
    final asr = FakeAsrEngine()..nextText = '你好';
    final llm = FakeLlmClient(chunks: ['你好']);
    final vad = FakeVadEngine();
    final deps = await _deps(asr: asr, llm: llm, vad: vad);

    await deps.conversationService.downloadInitialModels(null);
    await deps.settings.setLlmApiKey('k');
    await deps.conversationService.start();
    expect(deps.conversationService.phase, ConversationPhase.listening);

    vad.emitSegment(Float32List(160));

    await _waitFor(
      () => deps.conversationService.phase == ConversationPhase.listening,
    );

    final msgs = deps.conversationService.messages;
    expect(msgs.length, 2);
    expect(msgs[0].role, ConversationRole.user);
    expect(msgs[0].content, '你好');
    expect(msgs[0].speakerName, isNull, reason: '未知说话人应无名字');
    expect(msgs[1].role, ConversationRole.assistant);
    expect(deps.conversationService.currentSpeaker, isNull);

    // 系统提示注入"未知用户"。
    final sys = llm.capturedMessages.first
        .firstWhere((m) => m.role == 'system')
        .content;
    expect(sys, contains('未知用户'));
  });

  test('已注册说话人:声纹识别 → 名字路由 + 备注注入提示词', () async {
    final asr = FakeAsrEngine()..nextText = '帮我查一下';
    final speaker = FakeSpeakerEngine()..nextName = '张三';
    final llm = FakeLlmClient(chunks: ['好的,张三']);
    final vad = FakeVadEngine();
    final deps = await _deps(asr: asr, speaker: speaker, llm: llm, vad: vad);

    // 下载声纹模型并注册张三。
    await deps.modelManager
        .downloadModel(ModelCatalog.byId(kLegacyVoiceprintModelId)!);
    await deps.voiceprintService.enroll(
      name: '张三',
      note: '同事',
      samples: [Float32List(160)],
    );

    await deps.conversationService.downloadInitialModels(null);
    await deps.settings.setLlmApiKey('k');
    await deps.conversationService.start();
    vad.emitSegment(Float32List(160));

    await _waitFor(
      () => deps.conversationService.phase == ConversationPhase.listening,
    );

    expect(deps.conversationService.currentSpeaker, '张三');
    final msgs = deps.conversationService.messages;
    expect(msgs.first.speakerName, '张三');

    final sys = llm.capturedMessages.first
        .firstWhere((m) => m.role == 'system')
        .content;
    expect(sys, contains('张三'));
    expect(sys, contains('同事'));
  });

  test('声纹门禁:未注册任何声纹时拒绝启动(fail-closed)', () async {
    final deps = await _deps();
    await deps.conversationService.downloadInitialModels(null);
    await deps.settings.setLlmApiKey('k');
    await deps.settings.setVoiceprintGateEnabled(true);

    await deps.conversationService.start();

    expect(deps.conversationService.phase, ConversationPhase.error);
    expect(deps.conversationService.lastError, 'voiceprintGateNoProfiles');
    expect(deps.conversationService.isMicActive, isFalse);
  });

  test('声纹门禁:不在白名单的人不跑 ASR、不落库、不问 LLM', () async {
    final asr = FakeAsrEngine()..nextText = '帮我查一下';
    final speaker = FakeSpeakerEngine(); // nextName 为空 = 未匹配
    final llm = FakeLlmClient(chunks: ['好的']);
    final vad = FakeVadEngine();
    final deps = await _deps(asr: asr, speaker: speaker, llm: llm, vad: vad);

    await deps.conversationService.downloadInitialModels(null);
    await deps.settings.setLlmApiKey('k');
    await deps.modelManager
        .downloadModel(ModelCatalog.byId(kLegacyVoiceprintModelId)!);
    await deps.voiceprintService.enroll(
      name: '张三',
      note: '同事',
      samples: [Float32List(160)],
    );
    await deps.settings.setVoiceprintGateEnabled(true);

    await deps.conversationService.start();
    vad.emitSegment(Float32List(160));

    // 等拒绝语播完、回到聆听态。
    await _waitFor(
      () => deps.conversationService.phase == ConversationPhase.listening,
    );

    expect(asr.recognizeCalls, 0, reason: '门禁拒绝应发生在 ASR 之前');
    expect(llm.capturedMessages, isEmpty, reason: '拒绝不该问 LLM');
    expect(deps.conversationService.messages, isEmpty,
        reason: '未注册者的语音不落库');
    expect(deps.conversationService.currentSpeaker, isNull);
  });

  test('声纹门禁:白名单内的人正常对话', () async {
    final asr = FakeAsrEngine()..nextText = '你好';
    final speaker = FakeSpeakerEngine()..nextName = '张三';
    final llm = FakeLlmClient(chunks: ['好的']);
    final vad = FakeVadEngine();
    final deps = await _deps(asr: asr, speaker: speaker, llm: llm, vad: vad);

    await deps.conversationService.downloadInitialModels(null);
    await deps.settings.setLlmApiKey('k');
    await deps.modelManager
        .downloadModel(ModelCatalog.byId(kLegacyVoiceprintModelId)!);
    await deps.voiceprintService.enroll(
      name: '张三',
      note: '同事',
      samples: [Float32List(160)],
    );
    await deps.settings.setVoiceprintGateEnabled(true);

    await deps.conversationService.start();
    vad.emitSegment(Float32List(160));

    await _waitFor(
      () => deps.conversationService.phase == ConversationPhase.listening,
    );

    expect(asr.recognizeCalls, 1);
    expect(llm.capturedMessages, isNotEmpty);
    expect(deps.conversationService.currentSpeaker, '张三');
  });

  test('静音时忽略语音段,不产生消息', () async {
    final asr = FakeAsrEngine()..nextText = '你好';
    final vad = FakeVadEngine();
    final deps = await _deps(asr: asr, vad: vad);

    await deps.conversationService.downloadInitialModels(null);
    await deps.settings.setLlmApiKey('k');
    await deps.conversationService.start();
    await deps.conversationService.toggleMute();
    expect(deps.conversationService.isMuted, isTrue);

    vad.emitSegment(Float32List(160));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(deps.conversationService.messages, isEmpty,
        reason: '静音时应忽略语音段');
  });

  test('stop 从聆听态回到 idle', () async {
    final deps = await _deps();
    await deps.conversationService.downloadInitialModels(null);
    await deps.settings.setLlmApiKey('k');

    await deps.conversationService.start();
    expect(deps.conversationService.phase, ConversationPhase.listening);

    await deps.conversationService.stop();
    expect(deps.conversationService.phase, ConversationPhase.idle);
  });

  test('LLM 失败进入 error 态并记录错误', () async {
    final asr = FakeAsrEngine()..nextText = '你好';
    final vad = FakeVadEngine();
    final deps = await _deps(asr: asr, vad: vad); // 未配 API key → LLM 抛错。

    await deps.conversationService.downloadInitialModels(null);
    await deps.conversationService.start();
    vad.emitSegment(Float32List(160));

    await _waitFor(
      () => deps.conversationService.phase == ConversationPhase.error,
    );
    expect(deps.conversationService.lastError, '未配置 LLM API Key');
  });

  test('多说话人单一时间线:按时间排序、用户消息带说话人徽章', () async {
    final asr = FakeAsrEngine()..nextText = '你好';
    final speaker = FakeSpeakerEngine()..nextName = '';
    final llm = FakeLlmClient(chunks: ['回复']);
    final vad = FakeVadEngine();
    final deps = await _deps(asr: asr, speaker: speaker, llm: llm, vad: vad);

    await deps.modelManager
        .downloadModel(ModelCatalog.byId(kLegacyVoiceprintModelId)!);
    await deps.voiceprintService.enroll(
      name: '张三',
      note: '同事',
      samples: [Float32List(160)],
    );
    await deps.conversationService.downloadInitialModels(null);
    await deps.settings.setLlmApiKey('k');
    await deps.conversationService.start();

    // 第一段:未知说话人。
    vad.emitSegment(Float32List(160));
    await _waitFor(
      () => deps.conversationService.phase == ConversationPhase.listening,
    );
    expect(deps.conversationService.messages.length, 2);
    expect(deps.conversationService.messages.first.speakerName, isNull);

    // 第二段:张三。
    speaker.nextName = '张三';
    vad.emitSegment(Float32List(160));
    await _waitFor(
      () => deps.conversationService.phase == ConversationPhase.listening,
    );

    // 单一时间线共 4 条,按时间升序,第二条用户消息带张三徽章。
    final msgs = deps.conversationService.messages;
    expect(msgs.length, 4);
    expect(
      msgs[0].createdAt <= msgs[2].createdAt,
      isTrue,
      reason: '单一时间线按时间排序',
    );
    expect(msgs[2].speakerName, '张三');
    expect(deps.conversationService.currentSpeaker, '张三');
  });

  test('clearHistory 清空当前历史', () async {
    final asr = FakeAsrEngine()..nextText = '你好';
    final vad = FakeVadEngine();
    final llm = FakeLlmClient(chunks: ['回复']);
    final deps = await _deps(asr: asr, llm: llm, vad: vad);

    await deps.conversationService.downloadInitialModels(null);
    await deps.settings.setLlmApiKey('k');
    await deps.conversationService.start();
    vad.emitSegment(Float32List(160));
    await _waitFor(
      () => deps.conversationService.phase == ConversationPhase.listening,
    );
    expect(deps.conversationService.messages.length, 2);

    await deps.conversationService.clearHistory();
    expect(deps.conversationService.messages, isEmpty);
  });

  test('deleteMessage 删除单条消息(内存 + 落库)', () async {
    final asr = FakeAsrEngine()..nextText = '你好';
    final llm = FakeLlmClient(chunks: ['回复']);
    final vad = FakeVadEngine();
    final store = MemoryConversationStore();
    final deps = await _deps(asr: asr, llm: llm, vad: vad, store: store);

    await deps.conversationService.downloadInitialModels(null);
    await deps.settings.setLlmApiKey('k');
    await deps.conversationService.start();
    vad.emitSegment(Float32List(160));
    await _waitFor(
      () => deps.conversationService.phase == ConversationPhase.listening,
    );
    expect(deps.conversationService.messages.length, 2);
    expect(await store.count(), 2);

    final firstId = deps.conversationService.messages.first.id!;
    await deps.conversationService.deleteMessage(firstId);
    expect(deps.conversationService.messages.length, 1);
    expect(await store.count(), 1);
  });

  test('sendText 文本模式:LLM 纯文本回复,不转 TTS', () async {
    final llm = FakeLlmClient(chunks: ['文本回复']);
    final deps = await _deps(llm: llm);
    await deps.settings.setLlmApiKey('k');

    await deps.conversationService.sendText('你好');

    expect(deps.conversationService.phase, ConversationPhase.idle);
    final msgs = deps.conversationService.messages;
    expect(msgs.length, 2);
    expect(msgs[0].role, ConversationRole.user);
    expect(msgs[0].content, '你好');
    expect(msgs[1].role, ConversationRole.assistant);
    expect(msgs[1].content, '文本回复');

    // 文本模式不转 TTS:引擎无合成记录。
    final fakeEngine = deps.engine as FakeTtsEngine;
    expect(fakeEngine.generatedTexts, isEmpty, reason: '文本模式不转 TTS');
  });
}
