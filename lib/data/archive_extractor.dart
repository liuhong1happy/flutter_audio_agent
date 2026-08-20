/// tar.bz2 模型包解压。
///
/// 使用 `archive` 包的 [BZip2Decoder] + [TarDecoder] 纯 Dart 解压,
/// 无需原生依赖,Android/iOS 均可运行。
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';

class ArchiveExtractor {
  const ArchiveExtractor({this.useCompute = true});

  /// 是否用后台 isolate 解压大文件(true 默认;测试环境可关闭避免
  /// fake-async 区内派生 isolate 挂起)。
  final bool useCompute;

  /// 解压 [archivePath](tar.bz2) 到 [outputDir]。
  ///
  /// 返回解压出的顶层目录名(若有)。sherpa-onnx 的模型包通常是一个
  /// 顶层目录,内含 model.onnx/tokens.txt 等。
  Future<String?> extractTarBz2({
    required String archivePath,
    required String outputDir,
  }) async {
    final archiveFile = File(archivePath);
    if (!await archiveFile.exists()) {
      throw StateError('归档不存在: $archivePath');
    }

    final bz2Bytes = await archiveFile.readAsBytes();
    // 大文件在后台执行,避免阻塞 UI。
    final rootName = useCompute
        ? await compute(_decodeInIsolate, _DecodeArg(bz2Bytes, outputDir))
        : _decodeInIsolate(_DecodeArg(bz2Bytes, outputDir));

    // 清理压缩包,节省磁盘。
    try {
      await archiveFile.delete();
    } on FileSystemException {
      // 删除失败不影响解压结果。
    }
    return rootName;
  }

  static String? _decodeInIsolate(_DecodeArg arg) {
    final bz2 = BZip2Decoder();
    final tarBytes = bz2.decodeBytes(arg.bytes);
    final archive = TarDecoder().decodeBytes(tarBytes);

    final out = Directory(arg.outputDir);
    out.createSync(recursive: true);

    String? topRoot;
    for (final entry in archive) {
      if (entry.isDirectory) {
        final dir = Directory('${arg.outputDir}${Platform.pathSeparator}${entry.name}');
        dir.createSync(recursive: true);
        continue;
      }
      final name = entry.name;
      // 防目录穿越。
      final safeName = _sanitizeRelative(name);
      if (safeName == null) continue;
      final firstSegment = safeName.split('/').first;
      topRoot ??= firstSegment;

      final target = File('${arg.outputDir}${Platform.pathSeparator}${safeName.replaceAll('/', Platform.pathSeparator)}');
      target.parent.createSync(recursive: true);
      final bytes = entry.content;
      target.writeAsBytesSync(bytes, flush: true);
    }
    return topRoot;
  }

  static String? _sanitizeRelative(String name) {
    final normalized = name.replaceAll('\\', '/');
    if (normalized.startsWith('/') ||
        normalized.contains('..') ||
        normalized.isEmpty) {
      return null;
    }
    return normalized;
  }
}

class _DecodeArg {
  const _DecodeArg(this.bytes, this.outputDir);
  final List<int> bytes;
  final String outputDir;
}
