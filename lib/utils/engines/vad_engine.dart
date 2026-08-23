/// VAD(语音活动检测)引擎:sherpa-onnx Silero VAD 在后台 isolate 运行。
///
/// 常开麦克风场景下持续喂样本,检测到语音段时通过 [onSegment] 回调。
/// 样本经 `TransferableTypedData` 零拷贝跨 isolate 交接。
library;

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'package:flutter_tts_demo/utils/isolate_bridge.dart';

/// 一个检测到的语音段。
@immutable
class VadSegment {
  const VadSegment({required this.samples, required this.start});

  /// 16kHz 单声道 float32 采样。
  final Float32List samples;

  /// 段起始采样下标。
  final int start;
}

/// VAD 引擎(懒加载,独立 isolate)。
class VadEngine {
  VadEngine()
      : _bridge = IsolateBridge(_workerEntry, debugName: 'sherpa-vad-worker') {
    _sub = _bridge.events.listen(_onEvent);
  }

  final IsolateBridge _bridge;
  late final StreamSubscription<Object?> _sub;
  bool _loaded = false;

  /// 检测到语音段时回调。
  void Function(VadSegment segment)? onSegment;

  bool get isLoaded => _loaded;

  void _onEvent(Object? payload) {
    if (payload is _VadSegmentEvent) {
      final Float32List samples;
      final s = payload.samples;
      if (s is TransferableTypedData) {
        samples = s.materialize().asFloat32List();
      } else {
        samples = s as Float32List;
      }
      onSegment?.call(VadSegment(samples: samples, start: payload.start));
    }
  }

  Future<void> load({
    required String model,
    double threshold = 0.5,
    double minSilenceDuration = 0.5,
    double minSpeechDuration = 0.25,
    int windowSize = 512,
    double maxSpeechDuration = 15.0,
    int sampleRate = 16000,
    double bufferSizeInSeconds = 60,
  }) async {
    final result = await _bridge.request('load', _VadLoadPayload(
      model: model,
      threshold: threshold,
      minSilenceDuration: minSilenceDuration,
      minSpeechDuration: minSpeechDuration,
      windowSize: windowSize,
      maxSpeechDuration: maxSpeechDuration,
      sampleRate: sampleRate,
      bufferSizeInSeconds: bufferSizeInSeconds,
    ));
    if (result != true) {
      throw StateError('VAD 加载失败');
    }
    _loaded = true;
  }

  /// 持续喂样本(单向,不阻塞)。
  Future<void> addSamples(Float32List samples) {
    if (samples.isEmpty) return Future.value();
    return _bridge.fire(
      'add',
      TransferableTypedData.fromList([samples]),
    );
  }

  Future<void> reset() => _bridge.request('reset', null);
  Future<void> flush() => _bridge.request('flush', null);
  Future<void> clear() => _bridge.request('clear', null);

  void dispose() {
    _loaded = false;
    _sub.cancel();
    _bridge.dispose();
  }
}

class _VadLoadPayload {
  const _VadLoadPayload({
    required this.model,
    required this.threshold,
    required this.minSilenceDuration,
    required this.minSpeechDuration,
    required this.windowSize,
    required this.maxSpeechDuration,
    required this.sampleRate,
    required this.bufferSizeInSeconds,
  });
  final String model;
  final double threshold;
  final double minSilenceDuration;
  final double minSpeechDuration;
  final int windowSize;
  final double maxSpeechDuration;
  final int sampleRate;
  final double bufferSizeInSeconds;
}

/// worker→main 的语音段事件(样本零拷贝)。
class _VadSegmentEvent {
  const _VadSegmentEvent({required this.samples, required this.start});
  final Object samples; // TransferableTypedData | Float32List
  final int start;
}

void _workerEntry(SendPort mainPort) {
  sherpa_onnx.initBindings();
  sherpa_onnx.VoiceActivityDetector? vad;
  final control = ReceivePort();
  mainPort.send(control.sendPort);

  control.listen((msg) {
    try {
      if (msg is BridgeRequest) {
        switch (msg.kind) {
          case 'load':
            final p = msg.payload as _VadLoadPayload;
            vad?.free();
            vad = sherpa_onnx.VoiceActivityDetector(
              config: sherpa_onnx.VadModelConfig(
                sileroVad: sherpa_onnx.SileroVadModelConfig(
                  model: p.model,
                  threshold: p.threshold,
                  minSilenceDuration: p.minSilenceDuration,
                  minSpeechDuration: p.minSpeechDuration,
                  windowSize: p.windowSize,
                  maxSpeechDuration: p.maxSpeechDuration,
                ),
                sampleRate: p.sampleRate,
                provider: 'cpu',
              ),
              bufferSizeInSeconds: p.bufferSizeInSeconds,
            );
            mainPort.send(BridgeReply(id: msg.id, payload: true));
          case 'reset':
            vad?.reset();
            mainPort.send(BridgeReply(id: msg.id, payload: true));
          case 'flush':
            vad?.flush();
            mainPort.send(BridgeReply(id: msg.id, payload: true));
          case 'clear':
            vad?.clear();
            mainPort.send(BridgeReply(id: msg.id, payload: true));
          default:
            mainPort.send(BridgeReply(id: msg.id, error: '未知命令'));
        }
      } else if (msg is BridgeFire) {
        if (msg.kind == 'add') {
          final samples =
              (msg.payload as TransferableTypedData).materialize().asFloat32List();
          vad?.acceptWaveform(samples);
          _drainSegments(mainPort, vad);
        }
      }
    } catch (e, stack) {
      debugPrint('VAD worker error: $e\n$stack');
      if (msg is BridgeRequest) {
        mainPort.send(BridgeReply(id: msg.id, error: '$e'));
      }
    }
  });
}

void _drainSegments(
  SendPort mainPort,
  sherpa_onnx.VoiceActivityDetector? vad,
) {
  if (vad == null) return;
  while (!vad.isEmpty()) {
    final seg = vad.front();
    vad.pop();
    final Object samples = seg.samples.isNotEmpty
        ? TransferableTypedData.fromList([seg.samples])
        : Float32List(0);
    mainPort.send(BridgeEvent(
      kind: 'segment',
      payload: _VadSegmentEvent(samples: samples, start: seg.start),
    ));
  }
}
