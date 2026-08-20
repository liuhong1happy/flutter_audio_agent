/// 内置 TTS 模型目录。
///
/// 条目数据来自 sherpa-onnx 官方 `tts-models` release
/// (https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models),
/// tar.bz2 大小来自 release 资产 API,内部文件结构来自官方文档与示例。
library;

import '../models/tts_model.dart';

/// GitHub release 资产统一前缀。
const String kTtsModelsReleaseBase =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models';

class ModelCatalog {
  const ModelCatalog();

  /// 全部可下载模型。
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
  ];

  static TtsModel? byId(String? id) {
    if (id == null) return null;
    for (final m in all) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// 返回支持多音色的模型列表(sid 可调)。
  static List<TtsModel> multiSpeaker() =>
      all.where((m) => m.speakers > 1).toList();
}
