/// patrol 测试共用的"假依赖"装配。
///
/// 使用假引擎/假下载器/假播放器,使集成测试不依赖真实模型与网络。
///
/// **v1.0.2 起默认把三块新能力也一起装上**(知识库 / 长期记忆 / 短期记忆):
/// 全内存 store + 确定性假嵌入引擎 + 假 LLM。不装的话这两个页面拿不到 Provider
/// (会直接抛),对话也会退化成"什么都不注入",新内容就无从端到端验证。
/// 需要验证"没有这些能力时的降级"时,传 null 显式关掉即可。
library;

import 'dart:io';

import 'package:flutter_tts_demo/data/app_dependencies.dart';
import 'package:flutter_tts_demo/data/archive_extractor.dart';
import 'package:flutter_tts_demo/data/knowledge_store.dart';
import 'package:flutter_tts_demo/data/memory_store.dart';
import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/data/session_memory_store.dart';
import 'package:flutter_tts_demo/utils/text_chunker.dart';

import '../test/support/fakes.dart';

/// 构造并初始化注入假实现的依赖,并预下载/选中默认模型。
///
/// 需要拿到某个 store 自己做断言(例如往会话里塞历史、给某人记一条记忆)时,
/// 自己 new 一个传进来即可 —— 传进来的实例就是装配用的那一个。
Future<AppDependencies> buildPatrolTestDeps({
  // ── 基础假实现 ──
  TtsSettings? settings,
  FakeLlmClient? llmClient,
  FakeVadEngine? vadEngine,
  FakeAsrEngine? asrEngine,
  FakeSpeakerEngine? speakerEngine,
  // 放慢合成/播放节奏,让"播放中"状态与高亮推进可被测试观测到。
  Duration segmentDuration = const Duration(milliseconds: 500),
  // ── v1.0.2:知识库 / 记忆(v1.0.2)──
  MemoryConversationStore? conversationStore,
  MemoryKnowledgeStore? knowledgeStore,
  MemoryMemoryStore? memoryStore,
  MemorySessionMemoryStore? sessionMemoryStore,
  FakeEmbeddingEngine? embeddingEngine,
}) async {
  final tempDir = Directory.systemTemp.createTempSync('patrol_');
  final deps = AppDependencies(
    appLock: FakeAppLockService(),
    settings: settings,
    engine: FakeTtsEngine(segmentDuration: segmentDuration),
    downloader: FakeModelDownloader(),
    chunker: TextChunker(enableJieba: false),
    extractor: const ArchiveExtractor(useCompute: false),
    player: FakeAudioPlaybackQueue(
      delayPerSegment: const Duration(milliseconds: 700),
    ),
    micRecorder: FakeMicRecorder(),
    vadEngine: vadEngine,
    asrEngine: asrEngine,
    speakerEngine: speakerEngine,
    // 假 LLM:测试里若不显式给一个,`streamChat` 会走真实 HTTP —— 集成测试
    // 不该依赖网络,所以这里也默认接上。
    llmClient: llmClient ?? FakeLlmClient(),
    conversationPlayer: FakeAudioPlaybackQueue(),
    conversationStore: conversationStore ?? MemoryConversationStore(),
    knowledgeStore: knowledgeStore ?? MemoryKnowledgeStore(),
    memoryStore: memoryStore ?? MemoryMemoryStore(),
    sessionMemoryStore: sessionMemoryStore ?? MemorySessionMemoryStore(),
    embeddingEngine: embeddingEngine ?? FakeEmbeddingEngine(),
    modelsDirProvider: () async => Directory('${tempDir.path}/models'),
    audioCacheDirProvider: () async => Directory('${tempDir.path}/audio'),
    cloneRefsDirProvider: () async => Directory('${tempDir.path}/clone_refs'),
  );
  await deps.init();

  final defaultModel = ModelCatalog.all.first;
  await deps.modelManager.downloadModel(defaultModel);
  await deps.settings.selectModel(defaultModel.id);
  return deps;
}
