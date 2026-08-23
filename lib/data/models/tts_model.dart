/// TTS 模型目录条目与本地下载状态实体。
library;

import 'package:flutter/foundation.dart';

/// sherpa-onnx 支持的 TTS 模型家族,决定 OfflineTts 使用哪个子配置。
enum TtsModelFamily {
  vits,
  kokoro,
}

/// 模型种类:决定下载形状、resolver 分支与引擎加载方式。
enum ModelKind {
  /// 普通 TTS(VITS/Kokoro),走 [TtsModelFamily]。
  tts,

  /// 离线 ASR(Paraformer,默认对话识别)。
  asrParaformer,

  /// 离线 ASR(SenseVoice,可选,支持情绪/语言)。
  asrSenseVoice,

  /// 声纹嵌入提取(3D-Speaker)。
  speaker,

  /// PocketTTS 零样本声音克隆。
  pocket,

  /// 语音活动检测(Silero VAD)。
  vad,
}

/// 下载格式:tar.bz2 需解压;rawFile 为单个裸文件(如 silero_vad.onnx)。
enum ModelDownloadFormat {
  tarBz2,
  rawFile,
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
    this.kind = ModelKind.tts,
    this.downloadFormat = ModelDownloadFormat.tarBz2,
    this.rawFileName,
    this.family = TtsModelFamily.vits,
    this.speakers = 1,
    this.sampleRate = 16000,
    this.ruleFsts = const [],
    this.multilingual = false,
  });

  /// 下载文件名 / 目录名,如 `vits-piper-zh_CN-xiao_ya-medium-int8`。
  final String id;

  final String displayName;

  final String description;

  /// 原始下载地址(GitHub release)。
  final String url;

  /// 压缩包/裸文件大小(字节),用于展示与剩余大小估算。
  final int tarBz2SizeBytes;

  final String license;

  /// 模型种类,决定 resolver/引擎如何加载。
  final ModelKind kind;

  /// 下载形状:tar.bz2 或单个裸文件。
  final ModelDownloadFormat downloadFormat;

  /// 当 [downloadFormat] 为 rawFile 时的落盘文件名,如 `silero_vad.onnx`。
  final String? rawFileName;

  /// 内置说话人数量(引擎的 sid 取值范围 0..speakers-1);非 TTS 为 0。
  final int speakers;

  /// 输出/输入采样率(约)。
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
