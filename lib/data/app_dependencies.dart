/// 手工依赖装配(DI)。
///
/// 生产环境由 [main] 用真实实现构造;patrol 集成测试可注入
/// 假下载器/假引擎/假麦克风/假 LLM,避免依赖真实网络与模型文件。
// ignore_for_file: prefer_initializing_formals
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_tts_demo/utils/asr_service.dart';
import 'package:flutter_tts_demo/utils/mic_recorder.dart';
import 'package:flutter_tts_demo/utils/conversation_service.dart';
import 'package:flutter_tts_demo/data/app_database.dart';
import 'package:flutter_tts_demo/data/conversation_store.dart';
import 'package:flutter_tts_demo/data/knowledge_store.dart';
import 'package:flutter_tts_demo/data/memory_store.dart';
import 'package:flutter_tts_demo/data/session_memory_store.dart';
import 'package:flutter_tts_demo/utils/memory/embedding_engine.dart';
import 'package:flutter_tts_demo/utils/memory/knowledge_service.dart';
import 'package:flutter_tts_demo/utils/memory/memory_service.dart';
import 'package:flutter_tts_demo/utils/memory/session_memory_service.dart';
import 'package:flutter_tts_demo/data/app_paths.dart';
import 'package:flutter_tts_demo/data/archive_extractor.dart';
import 'package:flutter_tts_demo/data/model_downloader.dart';
import 'package:flutter_tts_demo/data/model_files_resolver.dart';
import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/data/model_manager.dart';
import 'package:flutter_tts_demo/utils/llm_client.dart';
import 'package:flutter_tts_demo/utils/llm_service.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/utils/engines/asr_engine.dart';
import 'package:flutter_tts_demo/utils/engines/pocket_tts_engine.dart';
import 'package:flutter_tts_demo/utils/sequential_audio_player.dart';
import 'package:flutter_tts_demo/utils/engines/speaker_engine.dart';
import 'package:flutter_tts_demo/utils/text_chunker.dart';
import 'package:flutter_tts_demo/utils/app_lock_service.dart';
import 'package:flutter_tts_demo/utils/text_normalizer.dart';
import 'package:flutter_tts_demo/utils/engines/tts_engine.dart';
import 'package:flutter_tts_demo/utils/tts_streaming_service.dart';
import 'package:flutter_tts_demo/utils/engines/vad_engine.dart';
import 'package:flutter_tts_demo/utils/voice_cloning_service.dart';
import 'package:flutter_tts_demo/utils/voiceprint_service.dart';

class AppDependencies {
  AppDependencies({
    TtsEngine? engine,
    ModelDownloader? downloader,
    ArchiveExtractor? extractor,
    TextNormalizer? normalizer,
    TextChunker? chunker,
    AudioPlaybackQueue? player,
    Future<Directory> Function()? modelsDirProvider,
    Future<Directory> Function()? audioCacheDirProvider,
    Future<Directory> Function()? cloneRefsDirProvider,
    Future<String> Function()? conversationDbPathProvider,
    AppDatabase? appDatabase,
    KnowledgeStore? knowledgeStore,
    MemoryStore? memoryStore,
    SessionMemoryStore? sessionMemoryStore,
    EmbeddingEngine? embeddingEngine,
    TtsSettings? settings,
    VadEngine? vadEngine,
    AsrEngine? asrEngine,
    SpeakerEngine? speakerEngine,
    PocketTtsEngine? pocketEngine,
    MicRecorder? micRecorder,
    LlmClient? llmClient,
    AudioPlaybackQueue? conversationPlayer,
    ConversationStore? conversationStore,
    AppLockService? appLock,
  })  : engine = engine ?? SherpaTtsEngine(),
        settings = settings ?? TtsSettings(),
        appLock = appLock ?? LocalAuthAppLockService(),
        _downloader = downloader ?? HttpModelDownloader(),
        _extractor = extractor ?? const ArchiveExtractor(),
        _normalizer = normalizer ?? TextNormalizer(),
        _chunker = chunker ?? TextChunker(),
        _player = player,
        _vadEngine = vadEngine,
        _asrEngine = asrEngine,
        _speakerEngine = speakerEngine,
        _pocketEngine = pocketEngine,
        _micRecorder = micRecorder,
        _llmClient = llmClient,
        _conversationPlayer = conversationPlayer,
        _conversationStore = conversationStore,
        _modelsDirProvider = modelsDirProvider ?? AppPaths.modelsDir,
        _audioCacheDirProvider =
            audioCacheDirProvider ?? AppPaths.audioCacheDir,
        _cloneRefsDirProvider =
            cloneRefsDirProvider ?? AppPaths.cloneRefsDir,
        _conversationDbPathProvider =
            conversationDbPathProvider ?? AppPaths.conversationDbPath,
        _injectedAppDatabase = appDatabase,
        _knowledgeStore = knowledgeStore,
        _memoryStore = memoryStore,
        _sessionMemoryStore = sessionMemoryStore,
        _embeddingEngine = embeddingEngine;

  static AppDependencies? _instance;

  /// 全局单例(生产环境经 [AppDependencies.instance.init] 初始化一次)。
  static AppDependencies get instance => _instance ??= AppDependencies();

  /// 测试用:重置单例(避免跨用例状态污染)。
  static void resetInstance() => _instance = null;

  final TtsEngine engine;
  final TtsSettings settings;

  /// 设备认证门闩(保护声纹档案的写操作)。
  final AppLockService appLock;

  final ModelDownloader _downloader;
  final ArchiveExtractor _extractor;
  final TextNormalizer _normalizer;
  final TextChunker _chunker;
  final AudioPlaybackQueue? _player;
  final VadEngine? _vadEngine;
  final AsrEngine? _asrEngine;
  final SpeakerEngine? _speakerEngine;
  final PocketTtsEngine? _pocketEngine;
  final MicRecorder? _micRecorder;
  final LlmClient? _llmClient;
  final AudioPlaybackQueue? _conversationPlayer;
  final ConversationStore? _conversationStore;
  final Future<Directory> Function() _modelsDirProvider;
  final Future<Directory> Function() _audioCacheDirProvider;
  final Future<Directory> Function() _cloneRefsDirProvider;
  final Future<String> Function() _conversationDbPathProvider;
  final AppDatabase? _injectedAppDatabase;
  final KnowledgeStore? _knowledgeStore;
  final MemoryStore? _memoryStore;
  final SessionMemoryStore? _sessionMemoryStore;
  final EmbeddingEngine? _embeddingEngine;

  late final ModelManager modelManager;
  late final TtsStreamingService streamingService;
  late final AsrService asrService;
  late final VoiceprintService voiceprintService;
  late final VoiceCloningService voiceCloningService;
  late final LlmService llmService;

  /// 知识库检索(可空:测试未注入库时为 null,功能自动关闭)。
  late final KnowledgeService? knowledgeService;

  /// 长期记忆(可空)。
  late final MemoryService? memoryService;

  /// 短期记忆/会话分段(可空)。
  late final SessionMemoryService? sessionMemoryService;
  late final ConversationService conversationService;
  late final MicRecorder micRecorder;
  late final Directory cloneRefsDir;

  /// 全应用共享的 SQLite 库(会话历史 + 知识库 + 记忆)。
  ///
  /// **可能为 null**:测试中各 store 都以内存实现注入,不需要真库;
  /// 而默认库路径来自 `path_provider`,在单元测试里不可用(见 init 中的说明)。
  /// **生产环境走默认分支,必然非 null。**
  AppDatabase? appDatabase;
  bool _initialized = false;

  /// 异步初始化(加载持久化设置、计算目录、装配依赖)。幂等。
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await settings.load();

    final modelsDir = await _modelsDirProvider();
    final audioCacheDir = await _audioCacheDirProvider();
    cloneRefsDir = await _cloneRefsDirProvider();

    modelManager = ModelManager(
      modelsDir: modelsDir,
      audioCacheDir: audioCacheDir,
      downloader: _downloader,
      extractor: _extractor,
      resolver: const ModelFilesResolver(),
      settings: settings,
    );
    await modelManager.load();

    streamingService = TtsStreamingService(
      normalizer: _normalizer,
      chunker: _chunker,
      engine: engine,
      modelManager: modelManager,
      settings: settings,
      player: _player,
    );
    // 恢复持久化的气泡历史(含毫秒级耗时统计)。
    await streamingService.loadHistory();

    // 对话相关服务(懒加载引擎,不在此预加载模型)。
    micRecorder = _micRecorder ?? RecordMicRecorder();
    asrService = AsrService(
      modelManager: modelManager,
      settings: settings,
      engine: _asrEngine,
    );
    voiceprintService = VoiceprintService(
      modelManager: modelManager,
      settings: settings,
      engine: _speakerEngine,
    );
    voiceCloningService = VoiceCloningService(
      modelManager: modelManager,
      engine: _pocketEngine,
    );
    await voiceCloningService.load();
    // 只读档案、不加载 onnx:声纹管理页要在冷启动就显示已注册的人,
    // 不能依赖"先跑一次识别/录入"才把档案读出来。
    await voiceprintService.ensureStoreLoaded();
    llmService = LlmService(settings: settings, client: _llmClient);
    // 会话历史 / 知识库 / 记忆 **共用同一个库**(迁移只能有一处,见 AppDatabase)。
    //
    // ⚠️ **必须在"确实需要真库"时才去问路径**。默认路径来自 `path_provider`,
    // 单元测试里不可用(MissingPluginException)。原先的写法是
    // `_conversationStore ?? SqliteConversationStore(await _conversationDbPathProvider())`
    // —— `??` 的**短路求值**保证了"注入了内存 store 就不会碰路径";
    // 重构时把 `await` 挪到 `??` 外面就会让所有注入内存 store 的测试全挂。
    // 故这里显式保留这个惰性。
    final injectedStore = _conversationStore;
    final ConversationStore conversationStore;
    if (injectedStore != null) {
      appDatabase = _injectedAppDatabase;
      conversationStore = injectedStore;
    } else {
      appDatabase =
          _injectedAppDatabase ?? AppDatabase(await _conversationDbPathProvider());
      conversationStore = SqliteConversationStore(appDatabase!);
    }

    // ── 知识库 / 记忆(v1.0.2)──────────────────────────────────────────
    // 三者共用上面那个库。**可为 null**:测试常只注入内存 store、不碰真库,
    // 此时这几个服务不装配,对话自动退化为 v1.0.1 行为(不注入任何片段),
    // 而不是偷偷用一个"存完就没了"的内存实现假装在工作。
    final db = appDatabase;
    final knowledgeStore = _knowledgeStore ??
        (db == null ? null : SqliteKnowledgeStore(db));
    knowledgeService = knowledgeStore == null
        ? null
        : KnowledgeService(
            store: knowledgeStore,
            modelManager: modelManager,
            settings: settings,
            engine: _embeddingEngine,
          );

    final memStore =
        _memoryStore ?? (db == null ? null : SqliteMemoryStore(db));
    memoryService = memStore == null
        ? null
        : MemoryService(
            store: memStore,
            llm: llmService,
            currentModelId: () =>
                settings.embeddingModelId ?? kDefaultEmbeddingModelId,
            engine: _embeddingEngine,
            extractEveryTurns: settings.memoryExtractInterval,
          );

    final sessionStore = _sessionMemoryStore ??
        (db == null ? null : SqliteSessionMemoryStore(db));
    sessionMemoryService =
        sessionStore == null ? null : SessionMemoryService(store: sessionStore, llm: llmService);

    conversationService = ConversationService(
      modelManager: modelManager,
      settings: settings,
      asr: asrService,
      voiceprint: voiceprintService,
      cloning: voiceCloningService,
      llm: llmService,
      chunker: _chunker,
      ttsEngine: engine,
      streamingService: streamingService,
      mic: micRecorder,
      store: conversationStore,
      knowledge: knowledgeService,
      memory: memoryService,
      sessionMemory: sessionMemoryService,
      vad: _vadEngine,
      player: _conversationPlayer,
    );
    await conversationService.loadHistory();

    // 后台预加载当前所选模型(已加载则忽略),让首次朗读免去加载等待;
    // 加载期间 streamingService.modelLoading == true。
    unawaited(streamingService.prepareModel());
  }

  /// 清理全部缓存:模型 + 音频缓存 + 克隆参考 + 声纹 + 对话历史。
  Future<void> clearAllData() async {
    await modelManager.clearAllCaches();
    if (await cloneRefsDir.exists()) {
      await cloneRefsDir.delete(recursive: true);
    }
    await voiceCloningService.clearAll();
    await voiceprintService.clearAll();
    await conversationService.clearHistory();
  }
}
