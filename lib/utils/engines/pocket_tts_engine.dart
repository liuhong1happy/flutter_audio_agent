/// PocketTTS 声音克隆引擎:sherpa-onnx PocketTTS 在后台 isolate 运行。
///
/// 零样本克隆:无需参考文本,仅需 3–10s 参考音频(模型会自行重采样)。
library;

import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'package:flutter_tts_demo/data/model_files_resolver.dart';
import 'package:flutter_tts_demo/utils/isolate_bridge.dart';
import 'package:flutter_tts_demo/utils/engines/tts_engine.dart' show GeneratedAudioData;

/// PocketTTS 克隆引擎(懒加载,独立 isolate)。
class PocketTtsEngine {
  PocketTtsEngine()
      : _bridge = IsolateBridge(_workerEntry, debugName: 'sherpa-pocket-worker');

  final IsolateBridge _bridge;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> load({
    required PocketModelPaths paths,
    int numThreads = 2,
  }) async {
    final result = await _bridge.request('load', _PocketLoadPayload(
      lmFlow: paths.lmFlow,
      lmMain: paths.lmMain,
      encoder: paths.encoder,
      decoder: paths.decoder,
      textConditioner: paths.textConditioner,
      vocabJson: paths.vocabJson,
      tokenScoresJson: paths.tokenScoresJson,
      numThreads: numThreads,
    ));
    if (result != true) {
      throw StateError('PocketTTS 加载失败');
    }
    _loaded = true;
  }

  Future<GeneratedAudioData> generate({
    required String text,
    required Float32List refSamples,
    required int refRate,
    int numSteps = 5,
    int seed = 42,
  }) async {
    if (!_loaded) throw StateError('PocketTTS 引擎未加载');
    final result = await _bridge.request('generate', _PocketGeneratePayload(
      text: text,
      refSamples: refSamples.isEmpty
          ? Float32List(0)
          : TransferableTypedData.fromList([refSamples]),
      refRate: refRate,
      numSteps: numSteps,
      seed: seed,
    ));
    if (result is! List || result.length < 2) {
      throw StateError('克隆合成返回异常');
    }
    final payload0 = result[0];
    final sampleRate = result[1] as int;
    final Float32List samples;
    if (payload0 is TransferableTypedData) {
      samples = payload0.materialize().asFloat32List();
    } else if (payload0 is Float32List) {
      samples = payload0;
    } else {
      throw StateError('克隆合成返回异常');
    }
    if (samples.isEmpty) throw StateError('克隆合成结果为空');
    return GeneratedAudioData(samples: samples, sampleRate: sampleRate);
  }

  void dispose() {
    _loaded = false;
    _bridge.dispose();
  }
}

class _PocketLoadPayload {
  const _PocketLoadPayload({
    required this.lmFlow,
    required this.lmMain,
    required this.encoder,
    required this.decoder,
    required this.textConditioner,
    required this.vocabJson,
    required this.tokenScoresJson,
    required this.numThreads,
  });
  final String lmFlow;
  final String lmMain;
  final String encoder;
  final String decoder;
  final String textConditioner;
  final String vocabJson;
  final String tokenScoresJson;
  final int numThreads;
}

class _PocketGeneratePayload {
  const _PocketGeneratePayload({
    required this.text,
    required this.refSamples,
    required this.refRate,
    required this.numSteps,
    required this.seed,
  });
  final String text;
  final Object refSamples; // TransferableTypedData | Float32List
  final int refRate;
  final int numSteps;
  final int seed;
}

void _workerEntry(SendPort mainPort) {
  sherpa_onnx.initBindings();
  sherpa_onnx.OfflineTts? tts;
  final control = ReceivePort();
  mainPort.send(control.sendPort);

  control.listen((msg) {
    if (msg is BridgeRequest) {
      try {
        switch (msg.kind) {
          case 'load':
            final p = msg.payload as _PocketLoadPayload;
            tts?.free();
            final loaded = sherpa_onnx.OfflineTts(sherpa_onnx.OfflineTtsConfig(
              model: sherpa_onnx.OfflineTtsModelConfig(
                pocket: sherpa_onnx.OfflineTtsPocketModelConfig(
                  lmFlow: p.lmFlow,
                  lmMain: p.lmMain,
                  encoder: p.encoder,
                  decoder: p.decoder,
                  textConditioner: p.textConditioner,
                  vocabJson: p.vocabJson,
                  tokenScoresJson: p.tokenScoresJson,
                  voiceEmbeddingCacheCapacity: 50,
                ),
                numThreads: p.numThreads,
                provider: 'cpu',
              ),
              maxNumSenetences: 1,
            ));
            tts = loaded;
            mainPort.send(BridgeReply(id: msg.id, payload: true));
          case 'generate':
            final g = msg.payload as _PocketGeneratePayload;
            final current = tts;
            if (current == null) {
              mainPort.send(BridgeReply(id: msg.id, error: 'PocketTTS 未加载'));
              break;
            }
            final ref = g.refSamples is TransferableTypedData
                ? (g.refSamples as TransferableTypedData)
                    .materialize()
                    .asFloat32List()
                : g.refSamples as Float32List;
            final audio = current.generateWithConfig(
              text: g.text,
              config: sherpa_onnx.OfflineTtsGenerationConfig(
                referenceAudio: ref.isEmpty ? null : ref,
                referenceSampleRate: g.refRate,
                numSteps: g.numSteps,
                extra: {'seed': g.seed},
              ),
            );
            final Object samplesPayload = audio.samples.isNotEmpty
                ? TransferableTypedData.fromList([audio.samples])
                : Float32List(0);
            mainPort.send(BridgeReply(
              id: msg.id,
              payload: [samplesPayload, audio.sampleRate],
            ));
          default:
            mainPort.send(BridgeReply(id: msg.id, error: '未知命令'));
        }
      } catch (e, stack) {
        debugPrint('Pocket worker error: $e\n$stack');
        mainPort.send(BridgeReply(id: msg.id, error: '$e'));
      }
    }
  });
}
