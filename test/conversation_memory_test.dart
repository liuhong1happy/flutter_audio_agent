/// 对话 × 知识库 × 记忆 的**端到端**集成测试。
///
/// 单元测试各自守住了一层,但真正会出问题的是**接起来之后**:
/// 检索结果有没有真的进提示词?未知说话人会不会捞到别人的记忆?
/// 知识库故障会不会把对话搞崩?这些只有端到端才测得出。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tts_demo/data/app_dependencies.dart';
import 'package:flutter_tts_demo/data/archive_extractor.dart';
import 'package:flutter_tts_demo/data/knowledge_store.dart';
import 'package:flutter_tts_demo/data/memory_store.dart';
import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/data/model_downloader.dart';
import 'package:flutter_tts_demo/data/session_memory_store.dart';
import 'package:flutter_tts_demo/utils/conversation_service.dart';
import 'package:flutter_tts_demo/utils/text_chunker.dart';

import 'support/fakes.dart';

/// 按**目录声明的精确体积**写字节的假下载器。
///
/// 多文件 raw 下载会逐文件做精确体积校验(用来抓"源返回了 HTML 错误页"),
/// 所以假下载器必须写对长度,否则测到的是"校验生效"而不是"下载成功"。
class _SizedDownloader implements ModelDownloader {
  _SizedDownloader() {
    final model = ModelCatalog.byId(kDefaultEmbeddingModelId)!;
    for (final f in model.rawFiles ?? const []) {
      _sizes[f.fileName] = f.sizeBytes;
    }
  }

  final Map<String, int> _sizes = {};
  final List<String> urls = [];

  @override
  Future<void> download({
    required String url,
    required String savePath,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    urls.add(url);
    final file = File(savePath);
    await file.parent.create(recursive: true);

    // tar.bz2 必须写**真归档**:ModelManager 会校验 bzip2 魔数,
    // 写裸字节会被拦下,导致对话三件套下载失败、start() 拒绝启动。
    if (savePath.endsWith('.tar.bz2')) {
      final bytes = buildFakeModelArchive();
      await file.writeAsBytes(bytes);
      onProgress?.call(bytes.length, bytes.length);
      return;
    }

    final name = savePath.split(Platform.pathSeparator).last;
    final n = _sizes[name] ?? 4096;
    await file.writeAsBytes(List<int>.filled(n, 7));
    onProgress?.call(n, n);
  }
}

Future<AppDependencies> _deps({
  FakeAsrEngine? asr,
  FakeSpeakerEngine? speaker,
  FakeVadEngine? vad,
  FakeLlmClient? llm,
  bool withMemoryStores = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final tempDir = Directory.systemTemp.createTempSync('convm_');
  final deps = AppDependencies(
    appLock: FakeAppLockService(),
    engine: FakeTtsEngine(segmentDuration: Duration.zero),
    downloader: _SizedDownloader(),
    chunker: TextChunker(enableJieba: false),
    extractor: const ArchiveExtractor(useCompute: false),
    player: FakeAudioPlaybackQueue(delayPerSegment: Duration.zero),
    conversationPlayer: FakeAudioPlaybackQueue(delayPerSegment: Duration.zero),
    conversationStore: MemoryConversationStore(),
    micRecorder: FakeMicRecorder(),
    vadEngine: vad ?? FakeVadEngine(),
    asrEngine: asr ?? FakeAsrEngine(),
    speakerEngine: speaker ?? FakeSpeakerEngine(),
    pocketEngine: FakePocketTtsEngine(),
    llmClient: llm ?? FakeLlmClient(),
    embeddingEngine: FakeEmbeddingEngine(),
    // 注意:一旦注入 conversationStore(内存版),appDatabase 就是 null,
    // 所以这里必须显式注入三个内存 store,否则知识库/记忆服务不会被装配。
    knowledgeStore: withMemoryStores ? MemoryKnowledgeStore() : null,
    memoryStore: withMemoryStores ? MemoryMemoryStore() : null,
    sessionMemoryStore: withMemoryStores ? MemorySessionMemoryStore() : null,
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

String _systemOf(FakeLlmClient llm, {int call = 0}) => llm.capturedMessages[call]
    .firstWhere((m) => m.role == 'system')
    .content;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('文本模式:知识库片段被检索并注入提示词', () async {
    final llm = FakeLlmClient(chunks: ['好的']);
    final deps = await _deps(llm: llm);

    // 嵌入模型"已下载"(完整性校验需要精确体积,故用 _SizedDownloader)。
    await deps.modelManager.downloadModel(
      ModelCatalog.byId(kDefaultEmbeddingModelId)!,
    );
    await deps.settings.setLlmApiKey('k');

    // 导入并等索引完成。
    await deps.knowledgeService!
        .importText(title: '产品手册', text: '语音对话系统由离线识别与离线合成两部分组成。');
    await deps.knowledgeService!.startBackfill();
    expect(deps.knowledgeService!.documents.single.isIndexed, isTrue,
        reason: '索引应已完成,否则检索不到');

    await deps.conversationService.sendText('语音对话系统怎么实现');

    final sys = _systemOf(llm);
    expect(sys, contains('【已知资料】'), reason: '知识库片段应被注入');
    expect(sys, contains('离线识别'));
    expect(sys, contains('产品手册'), reason: '应带来源标题');
    expect(deps.conversationService.lastContext!.knowledgeInjected, 1);
  });

  test('音频模式:当前说话人的长期记忆被注入', () async {
    final asr = FakeAsrEngine()..nextText = '我喜欢什么';
    final speaker = FakeSpeakerEngine()..nextName = '张三';
    final llm = FakeLlmClient(chunks: ['你喜欢咖啡']);
    final vad = FakeVadEngine();
    final deps = await _deps(asr: asr, speaker: speaker, llm: llm, vad: vad);

    // 注册张三(记忆要挂在他身上)。
    await deps.modelManager
        .downloadModel(ModelCatalog.byId(kLegacyVoiceprintModelId)!);
    await deps.voiceprintService.enroll(
      name: '张三',
      note: '',
      samples: [Float32List(160)],
    );
    await deps.conversationService.downloadInitialModels(null);
    await deps.settings.setLlmApiKey('k');

    // 先让嵌入引擎就绪,再写记忆 —— 否则记忆没有向量,检索不到。
    await deps.modelManager
        .downloadModel(ModelCatalog.byId(kDefaultEmbeddingModelId)!);
    await deps.knowledgeService!.ensureEngineLoaded();
    await deps.memoryService!.remember(speaker: '张三', content: '喜欢喝咖啡');

    await deps.conversationService.start();
    vad.emitSegment(Float32List(160));
    await _waitFor(
      () => deps.conversationService.phase == ConversationPhase.listening,
    );

    final sys = _systemOf(llm);
    expect(sys, contains('【关于当前说话人的长期记忆】'));
    expect(sys, contains('喜欢喝咖啡'));
    expect(deps.conversationService.lastContext!.memoriesInjected, 1);
  });

  test('**音频模式 + 未知说话人:绝不注入任何记忆**(跨人泄漏防线)', () async {
    final asr = FakeAsrEngine()..nextText = '我喜欢什么';
    // 声纹认不出这个人(未知)。
    final speaker = FakeSpeakerEngine()..nextName = '';
    final llm = FakeLlmClient(chunks: ['我不知道']);
    final vad = FakeVadEngine();
    final deps = await _deps(asr: asr, speaker: speaker, llm: llm, vad: vad);

    await deps.conversationService.downloadInitialModels(null);
    await deps.settings.setLlmApiKey('k');
    await deps.modelManager
        .downloadModel(ModelCatalog.byId(kDefaultEmbeddingModelId)!);
    await deps.knowledgeService!.ensureEngineLoaded();

    // 库里**确实**有张三的记忆 —— 陌生人绝不能捞到它。
    await deps.memoryService!.remember(speaker: '张三', content: '喜欢喝咖啡');
    expect(await deps.memoryService!.listFor('张三'), hasLength(1));

    await deps.conversationService.start();
    vad.emitSegment(Float32List(160));
    await _waitFor(
      () => deps.conversationService.phase == ConversationPhase.listening,
    );

    expect(deps.conversationService.currentSpeaker, isNull);
    final sys = _systemOf(llm);
    expect(sys, isNot(contains('喜欢喝咖啡')),
        reason: '未知说话人拿到别人的记忆 = 跨人泄漏,且听起来极自然');
    expect(sys, isNot(contains('长期记忆')));
    expect(deps.conversationService.lastContext!.memoriesInjected, 0);
  });

  test('知识库/记忆未装配时:对话照常,只是不注入', () async {
    final llm = FakeLlmClient(chunks: ['好的']);
    final deps = await _deps(llm: llm, withMemoryStores: false);
    expect(deps.knowledgeService, isNull);
    expect(deps.memoryService, isNull);

    await deps.settings.setLlmApiKey('k');
    await deps.conversationService.sendText('随便问点什么');

    final sys = _systemOf(llm);
    expect(sys, isNot(contains('【已知资料】')));
    expect(sys, isNot(contains('长期记忆')));
    // 但对话本身必须正常完成。
    expect(deps.conversationService.messages, hasLength(2));
  });

  test('知识库检索失败(模型未下载)⇒ 对话照常,只是不注入', () async {
    final llm = FakeLlmClient(chunks: ['好的']);
    final deps = await _deps(llm: llm);
    // 故意**不**下载嵌入模型。
    await deps.settings.setLlmApiKey('k');
    await deps.knowledgeService!
        .importText(title: 'A', text: '语音对话系统的内容。');

    await deps.conversationService.sendText('语音对话系统');

    expect(_systemOf(llm), isNot(contains('【已知资料】')));
    expect(deps.conversationService.messages, hasLength(2),
        reason: '检索失败不该影响对话');
    expect(deps.conversationService.phase, ConversationPhase.idle);
  });

  test('落库的消息带会话分段 id(否则永远不会被摘要)', () async {
    final llm = FakeLlmClient(chunks: ['好的']);
    final deps = await _deps(llm: llm);
    await deps.settings.setLlmApiKey('k');

    await deps.conversationService.sendText('第一句');

    final msgs = deps.conversationService.messages;
    expect(msgs, isNotEmpty);
    for (final m in msgs) {
      expect(m.sessionId, isNotNull, reason: '每条消息都必须归属某个会话段');
      expect(m.sessionId, isNotEmpty);
    }
    // 同一场对话内的消息应属同一段。
    expect(msgs.map((m) => m.sessionId).toSet(), hasLength(1));
  });

  test('编排器在提示词里保留身份与备注(不因加料而丢)', () async {
    final asr = FakeAsrEngine()..nextText = '帮我查一下';
    final speaker = FakeSpeakerEngine()..nextName = '张三';
    final llm = FakeLlmClient(chunks: ['好的']);
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
    vad.emitSegment(Float32List(160));
    await _waitFor(
      () => deps.conversationService.phase == ConversationPhase.listening,
    );

    final sys = _systemOf(llm);
    expect(sys, contains('张三'));
    expect(sys, contains('同事'));
    expect(sys, isNot(contains('未知用户')));
  });
}
