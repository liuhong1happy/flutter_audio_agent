/// 声纹嵌入引擎:sherpa-onnx 3D-Speaker 在后台 isolate 运行。
///
/// 嵌入提取用 [sherpa_onnx.OnlineStream](不是 OfflineStream)。本引擎按
/// "整段样本一次性喂入 → 直接 compute"处理,不做忙等,worker 天然串行,
/// 避免阻塞事件循环。
library;

import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'package:flutter_tts_demo/utils/isolate_bridge.dart';

/// 声纹引擎(懒加载,独立 isolate)。
class SpeakerEngine {
  SpeakerEngine()
      : _bridge = IsolateBridge(_workerEntry, debugName: 'sherpa-speaker-worker');

  final IsolateBridge _bridge;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> load({
    required String modelPath,
    int numThreads = 1,
  }) async {
    final result = await _bridge.request('load', _SpeakerLoadPayload(
      model: modelPath,
      numThreads: numThreads,
    ));
    if (result != true) {
      throw StateError('声纹引擎加载失败');
    }
    _loaded = true;
  }

  /// 提取一段语音的嵌入(192 维)。样本一次性喂入。
  Future<Float32List> extract(Float32List samples, int sampleRate) async {
    if (!_loaded) throw StateError('声纹引擎未加载');
    final result = await _bridge.request('extract', _SpeakerExtractPayload(
      samples: samples.isEmpty
          ? Float32List(0)
          : TransferableTypedData.fromList([samples]),
      sampleRate: sampleRate,
    ));
    if (result is! Float32List) throw StateError('声纹提取返回异常');
    return result;
  }

  /// 注册单个嵌入。
  Future<bool> add(String name, Float32List embedding) async {
    final r = await _bridge.request('add', _SpeakerEnrollPayload(
      name: name,
      embeddings: [embedding],
    ));
    return r == true;
  }

  /// 一人多段嵌入注册。
  Future<bool> addMulti(String name, List<Float32List> embeddings) async {
    final r = await _bridge.request('add', _SpeakerEnrollPayload(
      name: name,
      embeddings: embeddings,
    ));
    return r == true;
  }

  Future<bool> remove(String name) async {
    final r = await _bridge.request('remove', _SpeakerRemovePayload(name: name));
    return r == true;
  }

  /// 搜索最匹配的说话人,未匹配返回空字符串。
  Future<String> search(Float32List embedding, double threshold) async {
    final r = await _bridge.request('search', _SpeakerSearchPayload(
      embedding: embedding,
      threshold: threshold,
    ));
    return r as String? ?? '';
  }

  Future<bool> verify(String name, Float32List embedding, double threshold) async {
    final r = await _bridge.request('verify', _SpeakerVerifyPayload(
      name: name,
      embedding: embedding,
      threshold: threshold,
    ));
    return r == true;
  }

  void dispose() {
    _loaded = false;
    _bridge.dispose();
  }
}

class _SpeakerLoadPayload {
  const _SpeakerLoadPayload({required this.model, required this.numThreads});
  final String model;
  final int numThreads;
}

class _SpeakerExtractPayload {
  const _SpeakerExtractPayload({required this.samples, required this.sampleRate});
  final Object samples; // TransferableTypedData | Float32List
  final int sampleRate;
}

class _SpeakerEnrollPayload {
  const _SpeakerEnrollPayload({required this.name, required this.embeddings});
  final String name;
  final List<Float32List> embeddings;
}

class _SpeakerRemovePayload {
  const _SpeakerRemovePayload({required this.name});
  final String name;
}

class _SpeakerSearchPayload {
  const _SpeakerSearchPayload({required this.embedding, required this.threshold});
  final Float32List embedding;
  final double threshold;
}

class _SpeakerVerifyPayload {
  const _SpeakerVerifyPayload({
    required this.name,
    required this.embedding,
    required this.threshold,
  });
  final String name;
  final Float32List embedding;
  final double threshold;
}

void _workerEntry(SendPort mainPort) {
  sherpa_onnx.initBindings();
  sherpa_onnx.SpeakerEmbeddingExtractor? extractor;
  sherpa_onnx.SpeakerEmbeddingManager? manager;
  final control = ReceivePort();
  mainPort.send(control.sendPort);

  control.listen((msg) {
    if (msg is BridgeRequest) {
      try {
        switch (msg.kind) {
          case 'load':
            final p = msg.payload as _SpeakerLoadPayload;
            extractor?.free();
            manager?.free();
            extractor = sherpa_onnx.SpeakerEmbeddingExtractor(
              config: sherpa_onnx.SpeakerEmbeddingExtractorConfig(
                model: p.model,
                numThreads: p.numThreads,
                provider: 'cpu',
              ),
            );
            manager = sherpa_onnx.SpeakerEmbeddingManager(extractor!.dim);
            mainPort.send(BridgeReply(id: msg.id, payload: true));
          case 'extract':
            final g = msg.payload as _SpeakerExtractPayload;
            final ex = extractor;
            if (ex == null) {
              mainPort.send(BridgeReply(id: msg.id, error: '声纹引擎未加载'));
              break;
            }
            final samples = g.samples is TransferableTypedData
                ? (g.samples as TransferableTypedData).materialize().asFloat32List()
                : g.samples as Float32List;
            final stream = ex.createStream();
            stream.acceptWaveform(samples: samples, sampleRate: g.sampleRate);
            final emb = ex.compute(stream);
            stream.free();
            mainPort.send(BridgeReply(id: msg.id, payload: emb));
          case 'add':
            final e = msg.payload as _SpeakerEnrollPayload;
            final ok = manager?.addMulti(
                  name: e.name,
                  embeddingList: e.embeddings,
                ) ??
                false;
            mainPort.send(BridgeReply(id: msg.id, payload: ok));
          case 'remove':
            final r = msg.payload as _SpeakerRemovePayload;
            mainPort.send(BridgeReply(
              id: msg.id,
              payload: manager?.remove(r.name) ?? false,
            ));
          case 'search':
            final s = msg.payload as _SpeakerSearchPayload;
            mainPort.send(BridgeReply(
              id: msg.id,
              payload: manager?.search(
                    embedding: s.embedding,
                    threshold: s.threshold,
                  ) ??
                  '',
            ));
          case 'verify':
            final v = msg.payload as _SpeakerVerifyPayload;
            mainPort.send(BridgeReply(
              id: msg.id,
              payload: manager?.verify(
                    name: v.name,
                    embedding: v.embedding,
                    threshold: v.threshold,
                  ) ??
                  false,
            ));
          default:
            mainPort.send(BridgeReply(id: msg.id, error: '未知命令'));
        }
      } catch (e, stack) {
        debugPrint('Speaker worker error: $e\n$stack');
        mainPort.send(BridgeReply(id: msg.id, error: '$e'));
      }
    }
  });
}
