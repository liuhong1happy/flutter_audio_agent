/// TTS 模型下载管理(需求 1)。
///
/// 维护每个模型的下载状态/进度,持久化"已下载"标记,并提供
/// 删除模型与清理全部缓存的能力。
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dva/flutter_dva.dart';
import 'package:path/path.dart' as p;

import '../dva/app_dva.dart';
import '../dva/app_models.dart';
import '../models/tts_model.dart';
import '../models/tts_settings.dart';
import 'archive_extractor.dart';
import 'model_downloader.dart';
import 'model_files_resolver.dart';

/// 单个模型的下载生命周期状态。
enum DownloadStatus {
  none,
  downloading,
  extracting,
  ready,
  error,
}

/// 模型的实时下载状态快照。
@immutable
class ModelDownloadState {
  const ModelDownloadState({
    this.status = DownloadStatus.none,
    this.progress = 0,
    this.error,
  });

  final DownloadStatus status;

  /// 0.0 ~ 1.0。
  final double progress;
  final String? error;

  bool get isDownloading => status == DownloadStatus.downloading;
  bool get isReady => status == DownloadStatus.ready;

  ModelDownloadState copyWith({
    DownloadStatus? status,
    double? progress,
    String? error,
  }) {
    return ModelDownloadState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: error ?? this.error,
    );
  }
}

class ModelManager extends ChangeNotifier {
  ModelManager({
    required this.modelsDir,
    required this.audioCacheDir,
    required this.downloader,
    required this.extractor,
    required this.resolver,
    required this.settings,
  });

  /// 模型根目录:`.../sherpa_tts/models`。
  final Directory modelsDir;

  /// 合成音频临时目录(清理缓存时一并删除)。
  final Directory audioCacheDir;

  final ModelDownloader downloader;
  final ArchiveExtractor extractor;
  final ModelFilesResolver resolver;
  final TtsSettings settings;

  final Map<String, ModelDownloadState> _states = {};
  final Map<String, CancelToken> _cancelTokens = {};

  Set<String> _downloaded = {};
  Set<String> get downloaded => Set.unmodifiable(_downloaded);

  bool isDownloaded(String id) => _downloaded.contains(id);

  ModelDownloadState stateOf(TtsModel model) =>
      _states[model.id] ?? const ModelDownloadState();

  /// 是否有正在下载/解压的模型(用于 Tab 徽标)。
  bool get hasActiveDownloads => _states.values.any((s) => s.isDownloading ||
      s.status == DownloadStatus.extracting);

  /// 模型根目录:解压内容所在目录。
  String modelUnpackedDir(TtsModel model) =>
      p.join(modelsDir.path, model.id, 'unpacked');

  /// 下载中的压缩包路径。
  String modelArchivePath(TtsModel model) =>
      p.join(modelsDir.path, model.id, '${model.id}.tar.bz2');

  /// 下载地址(应用镜像前缀)。
  String effectiveUrl(TtsModel model) {
    final prefix = settings.mirrorPrefix;
    if (prefix.isEmpty) return model.url;
    return '$prefix${model.url}';
  }

  Future<void> load() async {
    final store = dvaStore();
    if (store != null) {
      final d = store.getStateByKey<DownloadsState>('downloads');
      _downloaded = d.downloadedIds.toSet();
    }
    notifyListeners();
  }

  Future<void> downloadModel(TtsModel model) async {
    if (stateOf(model).isDownloading) return;

    _setState(model, const ModelDownloadState(
      status: DownloadStatus.downloading,
      progress: 0,
    ));

    final cancelToken = CancelToken();
    _cancelTokens[model.id] = cancelToken;

    try {
      await downloader.download(
        url: effectiveUrl(model),
        savePath: modelArchivePath(model),
        cancelToken: cancelToken,
        onProgress: (received, total) {
          final progress = total > 0 ? received / total : 0.0;
          _setState(model, ModelDownloadState(
            status: DownloadStatus.downloading,
            progress: progress.clamp(0.0, 1.0),
          ));
        },
      );

      // 解压。
      _setState(model, const ModelDownloadState(
        status: DownloadStatus.extracting,
        progress: 1.0,
      ));
      await extractor.extractTarBz2(
        archivePath: modelArchivePath(model),
        outputDir: modelUnpackedDir(model),
      );

      // 校验关键文件是否齐全。
      final resolved = resolver.resolve(model, modelUnpackedDir(model));
      if (resolved == null || !resolved.isComplete) {
        throw StateError('模型文件不完整: ${model.id}');
      }

      _downloaded.add(model.id);
      await _persistDownloaded();
      _setState(model, const ModelDownloadState(
        status: DownloadStatus.ready,
        progress: 1.0,
      ));
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        _setState(model, const ModelDownloadState());
      } else {
        _setState(model, ModelDownloadState(
          status: DownloadStatus.error,
          error: '下载失败: ${e.message}',
        ));
      }
    } catch (e) {
      _setState(model, ModelDownloadState(
        status: DownloadStatus.error,
        error: '处理失败: $e',
      ));
    } finally {
      _cancelTokens.remove(model.id);
    }
  }

  void cancelDownload(TtsModel model) {
    final token = _cancelTokens[model.id];
    if (token == null) return;
    token.cancel();
    _setState(model, const ModelDownloadState());
  }

  /// 删除单个模型(需求 6:移除 TTS 模型)。
  Future<void> removeModel(TtsModel model) async {
    cancelDownload(model);
    final dir = Directory(modelUnpackedDir(model));
    if (await dir.exists()) await dir.delete(recursive: true);
    final root = Directory(p.join(modelsDir.path, model.id));
    if (await root.exists()) await root.delete(recursive: true);

    _downloaded.remove(model.id);
    _states.remove(model.id);
    await _persistDownloaded();
    notifyListeners();
  }

  /// 清理全部缓存(需求 6):删除所有模型 + 下载临时文件 + 音频缓存,
  /// 重置已下载标记;保留用户设置(模型选择/语速等)。
  Future<void> clearAllCaches() async {
    for (final token in _cancelTokens.values) {
      token.cancel();
    }
    _cancelTokens.clear();

    if (await modelsDir.exists()) {
      await modelsDir.delete(recursive: true);
    }
    if (await audioCacheDir.exists()) {
      await audioCacheDir.delete(recursive: true);
    }

    _downloaded.clear();
    _states.clear();
    await _persistDownloaded();
    notifyListeners();
  }

  /// 清理后剩余占用的字节数(粗略)。
  Future<int> totalBytesOnDisk() async {
    var bytes = 0;
    if (await modelsDir.exists()) {
      bytes += await _dirSize(modelsDir);
    }
    if (await audioCacheDir.exists()) {
      bytes += await _dirSize(audioCacheDir);
    }
    return bytes;
  }

  ResolvedModelPaths? resolveModel(TtsModel model) {
    if (!isDownloaded(model.id)) return null;
    return resolver.resolve(model, modelUnpackedDir(model));
  }

  void _setState(TtsModel model, ModelDownloadState state) {
    _states[model.id] = state;
    notifyListeners();
  }

  Future<void> _persistDownloaded() async {
    final store = dvaStore();
    if (store != null) {
      await store.dispatch(
        DvaAction('downloads/setDownloaded', _downloaded.toList()),
      );
    }
  }

  static Future<int> _dirSize(Directory dir) async {
    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } on FileSystemException {
          // 忽略无法读取的文件。
        }
      }
    }
    return total;
  }
}
