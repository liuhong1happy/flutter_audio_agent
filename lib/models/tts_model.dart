/// TTS 模型目录条目与本地下载状态实体。
library;

import 'package:flutter/foundation.dart';

/// sherpa-onnx 支持的模型家族,决定 OfflineTts 使用哪个子配置。
enum TtsModelFamily {
  vits,
  kokoro,
}

/// 模型目录中的一个可下载条目。
///
/// 仅描述"可下载什么"与"下载后引擎如何加载",不包含本地状态。
@immutable
class TtsModel {
  const TtsModel({
    required this.id,
    required this.displayName,
    required this.description,
    required this.url,
    required this.tarBz2SizeBytes,
    required this.license,
    required this.speakers,
    required this.sampleRate,
    required this.family,
    this.ruleFsts = const [],
    this.multilingual = false,
  });

  /// 下载文件名 / 目录名,如 `vits-piper-zh_CN-xiao_ya-medium-int8`。
  final String id;

  final String displayName;

  final String description;

  /// 原始下载地址(GitHub release `tts-models`)。
  final String url;

  /// tar.bz2 压缩包大小(字节),用于展示与剩余大小估算。
  final int tarBz2SizeBytes;

  final String license;

  /// 内置说话人数量(引擎的 sid 取值范围 0..speakers-1)。
  final int speakers;

  /// 输出采样率(约)。
  final int sampleRate;

  final TtsModelFamily family;

  /// 归一化规则文件名列表(位于模型根目录),如 `number.fst`。
  final List<String> ruleFsts;

  /// 是否支持中英混读。
  final bool multilingual;

  String get sizeLabel => _formatBytes(tarBz2SizeBytes);

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      final mb = bytes / (1024 * 1024);
      return mb >= 100 ? '${mb.round()}MB' : '${mb.toStringAsFixed(1)}MB';
    }
    if (bytes >= 1024) {
      final kb = bytes / 1024;
      return '${kb.round()}KB';
    }
    return '$bytes B';
  }

  @override
  String toString() => 'TtsModel($id)';
}
