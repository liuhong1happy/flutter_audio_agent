/// 内置模型目录(含 TTS / ASR / 声纹 / VAD / 声音克隆)。
///
/// 条目数据来自 sherpa-onnx 官方 release,大小来自 release 资产 API,
/// 内部文件结构来自官方文档与示例。
library;

import 'package:flutter_tts_demo/data/models/tts_model.dart';

/// GitHub release 资产统一前缀。
const String kTtsModelsReleaseBase =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models';

/// ASR 模型 release 前缀。
const String kAsrModelsReleaseBase =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models';

/// 声纹模型 release 前缀(官方 release 名确为 speaker-recongition-models,
/// 带拼写错误,勿改)。
const String kSpeakerModelsReleaseBase =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models';

/// 国内可用的 GitHub 加速代理(按可用性排序;实测于 2026-08)。
/// 下载时按顺序回退,直连 GitHub 作为最后兜底。
const List<String> kChinaGitHubProxies = [
  'https://ghfast.top/',
  'https://ghproxy.net/',
  'https://gh-proxy.com/',
  'https://ghps.cc/',
];

/// 对话三件套默认模型 id(VAD / ASR / TTS)。
const Map<String, String> kDefaultConversationModelIds = {
  'vad': 'silero_vad',
  'asr': 'sherpa-onnx-paraformer-zh-2023-09-14',
  'tts': 'vits-piper-zh_CN-xiao_ya-medium-int8',
};

class ModelCatalog {
  const ModelCatalog();

  /// 全部可下载模型(顺序稳定:`.first` 恒为默认 TTS piper 模型)。
  static const List<TtsModel> all = [
    TtsModel(
      id: 'vits-piper-zh_CN-xiao_ya-medium-int8',
      displayName: 'Piper 晓雅(中文, int8)',
      description: '中文女声,最小体积加载最快,适合先跑通全流程。',
      url: '$kTtsModelsReleaseBase/vits-piper-zh_CN-xiao_ya-medium-int8.tar.bz2',
      tarBz2SizeBytes: 14016124,
      license: 'MIT',
      speakers: 1,
      sampleRate: 22050,
      family: TtsModelFamily.vits,
      ruleFsts: ['phone.fst', 'date.fst', 'number.fst'],
    ),
    TtsModel(
      id: 'vits-zh-hf-fanchen-C',
      displayName: 'Fanchen C(中文, 187 音色)',
      description: '通用中文,187 个音色,适合演示自定义说话人。',
      url: '$kTtsModelsReleaseBase/vits-zh-hf-fanchen-C.tar.bz2',
      tarBz2SizeBytes: 119326431,
      license: 'LICENSE(随包)',
      speakers: 187,
      sampleRate: 16000,
      family: TtsModelFamily.vits,
      ruleFsts: ['phone.fst', 'date.fst', 'number.fst'],
    ),
    TtsModel(
      id: 'vits-melo-tts-zh_en',
      displayName: 'MeloTTS(中英混读)',
      description: '中英文混合朗读,44.1kHz,MIT 协议。',
      url: '$kTtsModelsReleaseBase/vits-melo-tts-zh_en.tar.bz2',
      tarBz2SizeBytes: 167006755,
      license: 'MIT',
      speakers: 1,
      sampleRate: 44100,
      family: TtsModelFamily.vits,
      ruleFsts: ['date.fst', 'number.fst'],
      multilingual: true,
    ),
    TtsModel(
      id: 'vits-zh-hf-theresa',
      displayName: 'Theresa(中文, 804 音色)',
      description: '音色选择最多的中文模型,22.05kHz。',
      url: '$kTtsModelsReleaseBase/vits-zh-hf-theresa.tar.bz2',
      tarBz2SizeBytes: 120596617,
      license: 'LICENSE(随包)',
      speakers: 804,
      sampleRate: 22050,
      family: TtsModelFamily.vits,
      ruleFsts: ['phone.fst', 'date.fst', 'number.fst'],
    ),
    TtsModel(
      id: 'kokoro-multi-lang-v1_0',
      displayName: 'Kokoro(中英混读, 53 音色)',
      description: '最佳中英混读质量,Apache-2.0。',
      url: '$kTtsModelsReleaseBase/kokoro-multi-lang-v1_0.tar.bz2',
      tarBz2SizeBytes: 349418188,
      license: 'Apache-2.0(依赖 eSpeak-ng GPL)',
      speakers: 53,
      sampleRate: 24000,
      family: TtsModelFamily.kokoro,
      ruleFsts: [],
      multilingual: true,
    ),

    // ── 对话/克隆/声纹相关(新增)─────────────────────────────────────

    TtsModel(
      id: 'sherpa-onnx-paraformer-zh-2023-09-14',
      displayName: 'Paraformer 中文识别',
      description: '离线中文语音识别(对话默认 ASR),约 234MB。',
      url: '$kAsrModelsReleaseBase/sherpa-onnx-paraformer-zh-2023-09-14.tar.bz2',
      tarBz2SizeBytes: 234051698,
      license: 'Apache-2.0',
      kind: ModelKind.asrParaformer,
      speakers: 0,
      sampleRate: 16000,
    ),
    TtsModel(
      id: 'sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17',
      displayName: 'SenseVoice 多语种识别(int8)',
      description: '中英日韩粤语音识别,附情绪/语种(可选),约 163MB。',
      url: '$kAsrModelsReleaseBase/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2',
      tarBz2SizeBytes: 163002883,
      license: 'Apache-2.0',
      kind: ModelKind.asrSenseVoice,
      speakers: 0,
      sampleRate: 16000,
    ),
    TtsModel(
      id: '3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k',
      displayName: '3D-Speaker 声纹识别',
      description: '说话人声纹嵌入(192 维),对话中自动识别说话人,约 40MB。',
      url: '$kSpeakerModelsReleaseBase/3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx',
      tarBz2SizeBytes: 39593761,
      license: 'Apache-2.0',
      kind: ModelKind.speaker,
      downloadFormat: ModelDownloadFormat.rawFile,
      rawFileName: '3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx',
      speakers: 0,
      sampleRate: 16000,
    ),
    TtsModel(
      id: 'silero_vad',
      displayName: 'Silero VAD',
      description: '语音活动检测(对话常开麦克风用),约 0.6MB。',
      url: '$kAsrModelsReleaseBase/silero_vad.onnx',
      tarBz2SizeBytes: 629000,
      license: 'MIT',
      kind: ModelKind.vad,
      downloadFormat: ModelDownloadFormat.rawFile,
      rawFileName: 'silero_vad.onnx',
      speakers: 0,
      sampleRate: 16000,
    ),
    TtsModel(
      id: 'sherpa-onnx-pocket-tts-int8-2026-01-26',
      displayName: 'PocketTTS 声音克隆(int8)',
      description: '零样本声音克隆(对话可选发音),约 98MB。',
      url: '$kTtsModelsReleaseBase/sherpa-onnx-pocket-tts-int8-2026-01-26.tar.bz2',
      tarBz2SizeBytes: 98336520,
      license: 'Apache-2.0',
      kind: ModelKind.pocket,
      speakers: 0,
      sampleRate: 24000,
    ),
  ];

  static TtsModel? byId(String? id) {
    if (id == null) return null;
    for (final m in all) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// 按种类取第一个模型(声纹/VAD/克隆等固定模型)。
  static TtsModel? byKind(ModelKind kind) {
    for (final m in all) {
      if (m.kind == kind) return m;
    }
    return null;
  }

  /// 返回支持多音色的 TTS 模型列表(sid 可调)。
  static List<TtsModel> multiSpeaker() => all
      .where((m) => m.kind == ModelKind.tts && m.speakers > 1)
      .toList();
}
