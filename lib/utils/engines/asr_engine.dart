/// 离线 ASR 引擎:sherpa-onnx Paraformer/SenseVoice 在后台 isolate 运行。
library;

import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'package:flutter_tts_demo/utils/isolate_bridge.dart';

/// 一次识别结果。
@immutable
class AsrResult {
  const AsrResult({required this.text, this.lang = '', this.emotion = ''});

  final String text;
  final String lang;
  final String emotion;
}

/// ASR 引擎(懒加载,独立 isolate)。
class AsrEngine {
  AsrEngine()
      : _bridge = IsolateBridge(_workerEntry, debugName: 'sherpa-asr-worker');

  final IsolateBridge _bridge;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> load({
    required String kind,
    required String modelPath,
    required String tokensPath,
    int numThreads = 2,
  }) async {
    final result = await _bridge.request('load', _AsrLoadPayload(
      kind: kind,
      model: modelPath,
      tokens: tokensPath,
      numThreads: numThreads,
    ));
    if (result != true) {
      throw StateError('ASR 加载失败');
    }
    _loaded = true;
  }

  Future<AsrResult> recognize(Float32List samples, int sampleRate) async {
    if (!_loaded) throw StateError('ASR 引擎未加载');
    final result = await _bridge.request('recognize', _AsrRecognizePayload(
      samples: samples.isEmpty
          ? Float32List(0)
          : TransferableTypedData.fromList([samples]),
      sampleRate: sampleRate,
    ));
    if (result is! _AsrResultPayload) {
      throw StateError('ASR 返回异常');
    }
    return AsrResult(text: result.text, lang: result.lang, emotion: result.emotion);
  }

  void dispose() {
    _loaded = false;
    _bridge.dispose();
  }
}

class _AsrLoadPayload {
  const _AsrLoadPayload({
    required this.kind,
    required this.model,
    required this.tokens,
    required this.numThreads,
  });
  final String kind;
  final String model;
  final String tokens;
  final int numThreads;
}

class _AsrRecognizePayload {
  const _AsrRecognizePayload({required this.samples, required this.sampleRate});
  final Object samples; // TransferableTypedData | Float32List
  final int sampleRate;
}

class _AsrResultPayload {
  const _AsrResultPayload({required this.text, required this.lang, required this.emotion});
  final String text;
  final String lang;
  final String emotion;
}

void _workerEntry(SendPort mainPort) {
  sherpa_onnx.initBindings();
  sherpa_onnx.OfflineRecognizer? recognizer;
  final control = ReceivePort();
  mainPort.send(control.sendPort);

  control.listen((msg) {
    if (msg is BridgeRequest) {
      try {
        switch (msg.kind) {
          case 'load':
            final p = msg.payload as _AsrLoadPayload;
            recognizer?.free();
            final modelConfig = p.kind == 'asrSenseVoice'
                ? sherpa_onnx.OfflineModelConfig(
                    senseVoice: sherpa_onnx.OfflineSenseVoiceModelConfig(
                      model: p.model,
                      language: 'auto',
                      useInverseTextNormalization: true,
                    ),
                    tokens: p.tokens,
                    numThreads: p.numThreads,
                    provider: 'cpu',
                  )
                : sherpa_onnx.OfflineModelConfig(
                    paraformer: sherpa_onnx.OfflineParaformerModelConfig(
                      model: p.model,
                    ),
                    tokens: p.tokens,
                    numThreads: p.numThreads,
                    provider: 'cpu',
                  );
            recognizer = sherpa_onnx.OfflineRecognizer(
              sherpa_onnx.OfflineRecognizerConfig(
                feat: const sherpa_onnx.FeatureConfig(
                  sampleRate: 16000,
                  featureDim: 80,
                ),
                model: modelConfig,
                decodingMethod: 'greedy_search',
              ),
            );
            mainPort.send(BridgeReply(id: msg.id, payload: true));
          case 'recognize':
            final g = msg.payload as _AsrRecognizePayload;
            final rec = recognizer;
            if (rec == null) {
              mainPort.send(BridgeReply(id: msg.id, error: 'ASR 未加载'));
              break;
            }
            final samples = g.samples is TransferableTypedData
                ? (g.samples as TransferableTypedData).materialize().asFloat32List()
                : g.samples as Float32List;
            final stream = rec.createStream();
            stream.acceptWaveform(samples: samples, sampleRate: g.sampleRate);
            rec.decode(stream);
            final r = rec.getResult(stream);
            stream.free();
            mainPort.send(BridgeReply(
              id: msg.id,
              payload: _AsrResultPayload(
                text: r.text,
                lang: r.lang,
                emotion: r.emotion,
              ),
            ));
          default:
            mainPort.send(BridgeReply(id: msg.id, error: '未知命令'));
        }
      } catch (e, stack) {
        debugPrint('ASR worker error: $e\n$stack');
        mainPort.send(BridgeReply(id: msg.id, error: '$e'));
      }
    }
  });
}
