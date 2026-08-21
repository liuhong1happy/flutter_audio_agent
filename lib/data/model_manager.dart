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
import 'model_catalog.dart';
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

  /// 是否已从持久化恢复(仅首次 [load] 生效,避免运行时状态被重复 load 覆盖)。
  bool _loaded = false;

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

  /// 下载地址候选列表(多镜像自动回退)。
  ///
  /// 顺序:手动镜像(设置里填)→ 国内 GitHub 代理 → 直连 GitHub(兜底)。
  /// 国内网络直连 GitHub 常失败,代理列表保证有可用的源。
  List<String> downloadCandidates(TtsModel model) {
    final list = <String>[];
    final manual = settings.mirrorPrefix.trim();
    if (manual.isNotEmpty) {
      list.add('$manual${model.url}');
    }
    for (final proxy in kChinaGitHubProxies) {
      list.add('$proxy${model.url}');
    }
    list.add(model.url);
    return list;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
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
      // 多镜像回退:依次尝试,成功即止。
      final candidates = downloadCandidates(model);
      var succeeded = false;
      String? lastError;

      for (var i = 0; i < candidates.length; i++) {
        if (cancelToken.isCancelled) break;
        final url = candidates[i];
        _setState(model, ModelDownloadState(
          status: DownloadStatus.downloading,
          progress: 0,
          error: candidates.length > 1 ? '尝试源 ${i + 1}/${candidates.length}' : null,
        ));
        try {
          await downloader.download(
            url: url,
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
          // 校验是否真的是 bzip2(tar.bz2 魔数 BZh),避免代理返回错误页面。
          if (!await _isValidBzip2(modelArchivePath(model))) {
            throw StateError('响应不是有效的 tar.bz2');
          }
          succeeded = true;
          break;
        } on DioException catch (e) {
          lastError = e.message;
          if (CancelToken.isCancel(e)) break;
          // 保留部分文件,支持断点续传:下一个源从 Range 偏移继续。
          // 继续下一个源。
        } catch (e) {
          lastError = '$e';
          if (cancelToken.isCancelled) break;
          // 文件完整但校验失败(魔数/解压/大小),删除以便重新完整下载。
          await _deleteIfExists(modelArchivePath(model));
          // 继续下一个源。
        }
      }

      if (!succeeded) {
        throw StateError('所有下载源均失败: $lastError');
      }

      // 解压。
      _setState(model, const ModelDownloadState(
        status: DownloadStatus.extracting,
        progress: 1.0,
      ));
      await extractor.extractTarBz2(
        archivePath: modelArchivePath(model),
        outputDir: modelUnpackedDir(model),
      );

      // 校验关键文件是否齐全 + 主模型非平凡大小(防止损坏/截断的空文件)。
      final resolved = resolver.resolve(model, modelUnpackedDir(model));
      if (resolved == null || !resolved.isComplete) {
        throw StateError('模型文件不完整: ${model.id}');
      }
      if (resolved.modelPath != null &&
          await _fileSizeBelow(resolved.modelPath!, _minOnnxBytes)) {
        throw StateError('模型主文件异常(过小,疑似损坏),请重新下载: ${model.id}');
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

  /// 主模型文件的最小合理大小:真实 onnx 数十 MB 以上,
  /// 远小于此视为下载/解压损坏。
  static const int _minOnnxBytes = 1024;

  static Future<bool> _fileSizeBelow(String path, int threshold) async {
    try {
      final f = File(path);
      if (!await f.exists()) return true;
      return await f.length() < threshold;
    } catch (_) {
      return true;
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

  static Future<void> _deleteIfExists(String path) async {
    final f = File(path);
    if (await f.exists()) {
      try {
        await f.delete();
      } on FileSystemException {
        // 忽略删除失败。
      }
    }
  }

  /// 校验文件是否为 tar.bz2(魔数 `BZh`),防止镜像返回 HTML 错误页。
  static Future<bool> _isValidBzip2(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return false;
      final raf = await f.open();
      try {
        final header = await raf.read(3);
        return header.length == 3 &&
            header[0] == 0x42 && // 'B'
            header[1] == 0x5A && // 'Z'
            header[2] == 0x68; // 'h'
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }
}
