/// patrol 测试共用的"假依赖"装配。
///
/// 使用假引擎/假下载器/假播放器,使集成测试不依赖真实模型与网络。
library;

import 'dart:io';

import 'package:flutter_tts_demo/data/app_dependencies.dart';
import 'package:flutter_tts_demo/data/archive_extractor.dart';
import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/utils/text_chunker.dart';

import '../test/support/fakes.dart';

/// 构造并初始化注入假实现的依赖,并预下载/选中默认模型。
Future<AppDependencies> buildPatrolTestDeps() async {
  final tempDir = Directory.systemTemp.createTempSync('patrol_');
  final deps = AppDependencies(
    appLock: FakeAppLockService(),
    // 放慢合成/播放节奏,让"播放中"状态与高亮推进可被测试观测到。
    engine: FakeTtsEngine(segmentDuration: const Duration(milliseconds: 500)),
    downloader: FakeModelDownloader(),
    chunker: TextChunker(enableJieba: false),
    extractor: const ArchiveExtractor(useCompute: false),
    player: FakeAudioPlaybackQueue(
      delayPerSegment: const Duration(milliseconds: 700),
    ),
    micRecorder: FakeMicRecorder(),
    conversationPlayer: FakeAudioPlaybackQueue(),
    conversationStore: MemoryConversationStore(),
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
