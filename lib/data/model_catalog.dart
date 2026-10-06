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

/// 合成页初始化推荐的默认模型(体积最小、加载最快,适合先跑通全流程)。
///
/// 值恰好等于 `kDefaultConversationModelIds['tts']`,也等于 `ModelCatalog.all.first`,
/// 但**显式写成常量**:目录重排不该静默改掉"推荐给用户的默认项"。
const String kDefaultSynthModelId = 'vits-piper-zh_CN-xiao_ya-medium-int8';

/// 文本嵌入模型的 ModelScope 基址。
///
/// ⚠️ 用 `Xenova/bge-small-zh-v1.5`(**单文件** ONNX)。**勿换**成
/// `onnx-community/bge-small-zh-v1.5-ONNX` —— 那份是 `.onnx`(168KB,仅图)+
/// `.onnx_data`(23.8MB,权重)的**外置数据**拆分格式,ORT 要求两者同名同目录,
/// 只下一个必然加载失败,而且报错不可读。
///
/// 另注:`huggingface.co` 本机直连不通,`modelscope.cn` 可用(2026-09-29 实测)。
const String kEmbeddingModelBase =
    'https://modelscope.cn/models/Xenova/bge-small-zh-v1.5/resolve/master';

/// 默认文本嵌入模型 id。
const String kDefaultEmbeddingModelId = 'bge-small-zh-v1.5';

/// 首个声纹模型(= 引入多模型选择之前唯一存在的那个)。
///
/// 专供"老档案迁移":旧数据的声纹档案没有 modelId 字段,一律归属此模型。
/// 不要用 [ModelCatalog.byKind] 做迁移——那按声明序取首个,有人重排目录
/// 就会把老档案迁到别的桶里,而嵌入空间不通用,识别结果会静默变垃圾。
const String kLegacyVoiceprintModelId =
    '3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k';

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
    // 第二个 Piper 中文基(男声)。与晓雅同一导出管线,**包结构已实测一致**
    // (onnx + tokens.txt + lexicon.txt + phone/date/number.fst),所以解析器与
    // 规则 fst 的接法零改动;体积也与晓雅同档(14.0 MB)。
    TtsModel(
      id: 'vits-piper-zh_CN-chaowen-medium-int8',
      displayName: 'Piper 超文(中文男声, int8)',
      description: '中文男声,14MB 档与晓雅同量级,加载快。',
      url: '$kTtsModelsReleaseBase/vits-piper-zh_CN-chaowen-medium-int8.tar.bz2',
      tarBz2SizeBytes: 14011298,
      license: 'CC0(见包内 MODEL_CARD)',
      speakers: 1,
      sampleRate: 22050,
      family: TtsModelFamily.vits,
      ruleFsts: ['phone.fst', 'date.fst', 'number.fst'],
    ),
    // Piper 中文女声(huayan)。**上游没有 int8 版**,只有 67 MB 的 fp32,
    // 体积是晓雅的 4.8 倍 —— 刻意排在晓雅/超文之后,不参与"默认最小"的选择。
    //
    // ⚠️ 与晓雅/超文**不是同一种导出**(已下包实测,勿照抄上面两条):
    //   - `phoneme_type: espeak`(**不是 pinyin**),包内是 `tokens.txt` +
    //     `espeak-ng-data/`(392 个文件),因此 **没有 phone/date/number.fst、
    //     也没有 lexicon.txt** —— 故这里不声明 ruleFsts(声明了也找不到文件)。
    //     数字/日期仍由应用自己的 `TextNormalizer` 归一化后再交给 espeak 音素化。
    //   - 许可:MODEL_CARD 写 **Unknown**(数据集来自 PlayVoice/HuaYan_TTS)。
    //   引擎侧走的是既有的 `ResolvedModelPaths.dataDir` 分支(Kokoro 同一条路)。
    TtsModel(
      id: 'vits-piper-zh_CN-huayan-medium',
      displayName: 'Piper huayan(中文女声, fp32)',
      description: '中文女声,espeak 音素化(无规则 fst);体积 67MB,下载较久。',
      url: '$kTtsModelsReleaseBase/vits-piper-zh_CN-huayan-medium.tar.bz2',
      tarBz2SizeBytes: 67255926,
      license: 'Unknown(见包内 MODEL_CARD)',
      speakers: 1,
      sampleRate: 22050,
      family: TtsModelFamily.vits,
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
      id: '3dspeaker_speech_campplus_sv_zh-cn_16k-common',
      displayName: 'CAMPPlus 声纹识别',
      description: '说话人声纹嵌入(192 维),跨域更稳,约 27MB。',
      url: '$kSpeakerModelsReleaseBase/'
          '3dspeaker_speech_campplus_sv_zh-cn_16k-common.onnx',
      tarBz2SizeBytes: 28281138,
      license: 'Apache-2.0',
      kind: ModelKind.speaker,
      downloadFormat: ModelDownloadFormat.rawFile,
      rawFileName: '3dspeaker_speech_campplus_sv_zh-cn_16k-common.onnx',
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
    // ── 文本嵌入(知识库 / 记忆检索)──────────────────────────────────
    // 与上面所有条目不同:它来自 **ModelScope** 而非 GitHub release
    // (huggingface.co 直连不通;modelscope.cn 实测 200 / 支持 Range / 24MB 约 2.6s)。
    // 且是**多文件 raw 下载**(onnx + tokenizer + vocab + config)。
    TtsModel(
      id: kDefaultEmbeddingModelId,
      displayName: 'BGE Small 中文(文本嵌入)',
      description: '本地文本语义向量,512 维。供知识库与长期记忆检索使用,全程离线。',
      // 多文件条目:`url` 为**基址**,实际下载地址 = `$url/$remotePath`。
      url: kEmbeddingModelBase,
      tarBz2SizeBytes: 0, // 体积由 rawFiles 求和(totalSizeBytes / sizeLabel)
      license: 'MIT',
      kind: ModelKind.embedding,
      downloadFormat: ModelDownloadFormat.rawFile,
      rawFiles: [
        ModelRawFile(
          remotePath: 'onnx/model_quantized.onnx',
          fileName: 'model_quantized.onnx',
          sizeBytes: 24010842,
        ),
        ModelRawFile(
          remotePath: 'tokenizer.json',
          fileName: 'tokenizer.json',
          sizeBytes: 439125,
        ),
        ModelRawFile(
          remotePath: 'vocab.txt',
          fileName: 'vocab.txt',
          sizeBytes: 109540,
        ),
        ModelRawFile(
          remotePath: 'config.json',
          fileName: 'config.json',
          sizeBytes: 716,
        ),
      ],
      speakers: 0,
      sampleRate: 0,
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

  /// 返回全部声纹模型(声明序,首个为默认)。
  static List<TtsModel> speakers() =>
      all.where((m) => m.kind == ModelKind.speaker).toList();
}
