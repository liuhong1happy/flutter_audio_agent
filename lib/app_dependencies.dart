/// 手工依赖装配(DI)。
///
/// 生产环境由 [main] 用真实实现构造;patrol 集成测试可注入
/// 假下载器/假引擎,避免依赖真实网络与模型文件。
// ignore_for_file: prefer_initializing_formals
library;

import 'dart:io';

import 'data/app_paths.dart';
import 'data/archive_extractor.dart';
import 'data/model_downloader.dart';
import 'data/model_files_resolver.dart';
import 'data/model_manager.dart';
import 'models/tts_settings.dart';
import 'tts/sequential_audio_player.dart';
import 'tts/text_chunker.dart';
import 'tts/text_normalizer.dart';
import 'tts/tts_engine.dart';
import 'tts/tts_streaming_service.dart';

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
    TtsSettings? settings,
  })  : engine = engine ?? SherpaTtsEngine(),
        settings = settings ?? TtsSettings(),
        _downloader = downloader ?? HttpModelDownloader(),
        _extractor = extractor ?? const ArchiveExtractor(),
        _normalizer = normalizer ?? TextNormalizer(),
        _chunker = chunker ?? TextChunker(),
        _player = player,
        _modelsDirProvider = modelsDirProvider ?? AppPaths.modelsDir,
        _audioCacheDirProvider =
            audioCacheDirProvider ?? AppPaths.audioCacheDir;

  final TtsEngine engine;
  final TtsSettings settings;

  final ModelDownloader _downloader;
  final ArchiveExtractor _extractor;
  final TextNormalizer _normalizer;
  final TextChunker _chunker;
  final AudioPlaybackQueue? _player;
  final Future<Directory> Function() _modelsDirProvider;
  final Future<Directory> Function() _audioCacheDirProvider;

  late final ModelManager modelManager;
  late final TtsStreamingService streamingService;

  /// 异步初始化(加载持久化设置、计算目录、装配依赖)。
  Future<void> init() async {
    await settings.load();

    final modelsDir = await _modelsDirProvider();
    final audioCacheDir = await _audioCacheDirProvider();

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
  }
}
