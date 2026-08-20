/// patrol 测试共用的"假依赖"装配。
///
/// 使用假引擎/假下载器/假播放器,使集成测试不依赖真实模型与网络。
library;

import 'dart:io';

import 'package:flutter_tts_demo/app_dependencies.dart';
import 'package:flutter_tts_demo/data/archive_extractor.dart';
import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/tts/text_chunker.dart';

import '../test/support/fakes.dart';

/// 构造并初始化注入假实现的依赖,并预下载/选中默认模型。
Future<AppDependencies> buildPatrolTestDeps() async {
  final tempDir = Directory.systemTemp.createTempSync('patrol_');
  final deps = AppDependencies(
    engine: FakeTtsEngine(segmentDuration: const Duration(milliseconds: 20)),
    downloader: FakeModelDownloader(),
    chunker: TextChunker(enableJieba: false),
    extractor: const ArchiveExtractor(useCompute: false),
    player: FakeAudioPlaybackQueue(),
    modelsDirProvider: () async => Directory('${tempDir.path}/models'),
    audioCacheDirProvider: () async => Directory('${tempDir.path}/audio'),
  );
  await deps.init();

  final defaultModel = ModelCatalog.all.first;
  await deps.modelManager.downloadModel(defaultModel);
  await deps.settings.selectModel(defaultModel.id);
  return deps;
}
