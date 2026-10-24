/// 离线 ASR 服务:按设置中的 `asrModelId` 懒加载引擎并识别。
// ignore_for_file: prefer_initializing_formals
library;

import 'package:flutter/foundation.dart';

import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/data/model_manager.dart';
import 'package:flutter_tts_demo/data/models/tts_model.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/utils/engines/asr_engine.dart';

class AsrService {
  AsrService({
    required ModelManager modelManager,
    required TtsSettings settings,
    AsrEngine? engine,
  })  : _modelManager = modelManager,
        _settings = settings,
        _engine = engine ?? AsrEngine();

  final ModelManager _modelManager;
  final TtsSettings _settings;
  final AsrEngine _engine;

  String? _loadedModelId;
  bool _loading = false;

  bool get isLoaded => _engine.isLoaded;
  bool get loading => _loading;

  /// 按当前设置的 ASR 模型解析并加载(已加载则忽略)。
  Future<void> ensureLoaded() async {
    final modelId = _settings.asrModelId;
    if (modelId == null) return;
    if (_engine.isLoaded && _loadedModelId == modelId) return;
    final model = ModelCatalog.byId(modelId);
    if (model == null) return;
    if (!_modelManager.isDownloaded(model.id)) return;
    final paths = _modelManager.resolveModel(model);
    if (paths == null || paths.tokensPath == null) return;

    // Transducer 没有单一 modelPath,而是 encoder/decoder/joiner 三件套;
    // 其余 ASR 族仍按 model+tokens 检查。
    final isTransducer = model.kind == ModelKind.asrTransducer;
    if (isTransducer) {
      if (!(paths.transducer?.isComplete ?? false)) return;
    } else if (paths.modelPath == null) {
      return;
    }

    _loading = true;
    try {
      await _engine.load(
        kind: model.kind.name,
        modelPath: paths.modelPath ?? '',
        tokensPath: paths.tokensPath!,
        encoderPath: paths.transducer?.encoder,
        decoderPath: paths.transducer?.decoder,
        joinerPath: paths.transducer?.joiner,
        numThreads: _settings.numThreads,
      );
      _loadedModelId = modelId;
    } finally {
      _loading = false;
    }
  }

  Future<AsrResult> recognize(Float32List samples, int sampleRate) async {
    await ensureLoaded();
    if (!_engine.isLoaded) {
      throw StateError('ASR 未就绪,请先下载并选择识别模型');
    }
    return _engine.recognize(samples, sampleRate);
  }

  void dispose() => _engine.dispose();
}
