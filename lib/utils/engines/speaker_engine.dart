/// 声纹嵌入引擎:sherpa-onnx 3D-Speaker 在后台 isolate 运行。
///
/// 嵌入提取用 [sherpa_onnx.OnlineStream](不是 OfflineStream)。本引擎按
/// "整段样本一次性喂入 → 直接 compute"处理,不做忙等,worker 天然串行,
/// 避免阻塞事件循环。
///
/// **按 modelId 分槽**:目录里可以同时存在多个声纹模型(ERes2Net、CAMPPlus
/// 等),它们的嵌入空间互不通用 —— 不同模型产出的向量不能互相比较。因此
/// worker 持有 `modelId → extractor + manager` 的映射,每个模型一套独立的
/// 提取器与档案管理器,任何命令都必须指明 modelId,槽不存在就报错,绝不
/// 回落到"当前某个"模型。
library;

import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'package:flutter_tts_demo/utils/isolate_bridge.dart';

/// 声纹引擎(懒加载,独立 isolate,每模型一槽)。
class SpeakerEngine {
  SpeakerEngine()
      : _bridge = IsolateBridge(_workerEntry, debugName: 'sherpa-speaker-worker');

  final IsolateBridge _bridge;

  /// 已加载成功的模型 id(worker 侧确实有对应槽)。
  final Set<String> _loadedModelIds = {};

  /// 是否已加载任意声纹模型。
  bool get isLoaded => _loadedModelIds.isNotEmpty;

  /// 指定模型是否已加载。
  bool isModelLoaded(String modelId) => _loadedModelIds.contains(modelId);

  /// 已加载的模型 id 快照。
  Set<String> get loadedModelIds => Set.unmodifiable(_loadedModelIds);

  /// 加载(或重新加载)某个声纹模型。重复加载同一 id 会重建槽。
  Future<void> load({
    required String modelId,
    required String modelPath,
    int numThreads = 1,
  }) async {
    final result = await _bridge.request('load', _SpeakerLoadPayload(
      modelId: modelId,
      model: modelPath,
      numThreads: numThreads,
    ));
    if (result != true) {
      _loadedModelIds.remove(modelId);
      throw StateError('声纹引擎加载失败');
    }
    _loadedModelIds.add(modelId);
  }

  /// 提取一段语音在指定模型下的嵌入(192 维)。样本一次性喂入。
  Future<Float32List> extract({
    required String modelId,
    required Float32List samples,
    required int sampleRate,
  }) async {
    final result = await _bridge.request('extract', _SpeakerExtractPayload(
      modelId: modelId,
      samples: samples.isEmpty
          ? Float32List(0)
          : TransferableTypedData.fromList([samples]),
      sampleRate: sampleRate,
    ));
    if (result is! Float32List) throw StateError('声纹提取返回异常');
    return result;
  }

  /// 注册单个嵌入。
  Future<bool> add({
    required String modelId,
    required String name,
    required Float32List embedding,
  }) async {
    final r = await _bridge.request('add', _SpeakerEnrollPayload(
      modelId: modelId,
      name: name,
      embeddings: [embedding],
    ));
    return r == true;
  }

  /// 一人多段嵌入注册。
  Future<bool> addMulti({
    required String modelId,
    required String name,
    required List<Float32List> embeddings,
  }) async {
    final r = await _bridge.request('add', _SpeakerEnrollPayload(
      modelId: modelId,
      name: name,
      embeddings: embeddings,
    ));
    return r == true;
  }

  Future<bool> remove({required String modelId, required String name}) async {
    final r = await _bridge.request(
      'remove',
      _SpeakerRemovePayload(modelId: modelId, name: name),
    );
    return r == true;
  }

  /// 在指定模型的档案中搜索最匹配的说话人,未匹配返回空字符串。
  Future<String> search({
    required String modelId,
    required Float32List embedding,
    required double threshold,
  }) async {
    final r = await _bridge.request('search', _SpeakerSearchPayload(
      modelId: modelId,
      embedding: embedding,
      threshold: threshold,
    ));
    return r as String? ?? '';
  }

  Future<bool> verify({
    required String modelId,
    required String name,
    required Float32List embedding,
    required double threshold,
  }) async {
    final r = await _bridge.request('verify', _SpeakerVerifyPayload(
      modelId: modelId,
      name: name,
      embedding: embedding,
      threshold: threshold,
    ));
    return r == true;
  }

  void dispose() {
    _loadedModelIds.clear();
    _bridge.dispose();
  }
}

class _SpeakerLoadPayload {
  const _SpeakerLoadPayload({
    required this.modelId,
    required this.model,
    required this.numThreads,
  });
  final String modelId;
  final String model;
  final int numThreads;
}

class _SpeakerExtractPayload {
  const _SpeakerExtractPayload({
    required this.modelId,
    required this.samples,
    required this.sampleRate,
  });
  final String modelId;
  final Object samples; // TransferableTypedData | Float32List
  final int sampleRate;
}

class _SpeakerEnrollPayload {
  const _SpeakerEnrollPayload({
    required this.modelId,
    required this.name,
    required this.embeddings,
  });
  final String modelId;
  final String name;
  final List<Float32List> embeddings;
}

class _SpeakerRemovePayload {
  const _SpeakerRemovePayload({required this.modelId, required this.name});
  final String modelId;
  final String name;
}

class _SpeakerSearchPayload {
  const _SpeakerSearchPayload({
    required this.modelId,
    required this.embedding,
    required this.threshold,
  });
  final String modelId;
  final Float32List embedding;
  final double threshold;
}

class _SpeakerVerifyPayload {
  const _SpeakerVerifyPayload({
    required this.modelId,
    required this.name,
    required this.embedding,
    required this.threshold,
  });
  final String modelId;
  final String name;
  final Float32List embedding;
  final double threshold;
}

void _workerEntry(SendPort mainPort) {
  sherpa_onnx.initBindings();
  final extractors = <String, sherpa_onnx.SpeakerEmbeddingExtractor>{};
  final managers = <String, sherpa_onnx.SpeakerEmbeddingManager>{};
  final control = ReceivePort();
  mainPort.send(control.sendPort);

  /// 取槽;缺失返回错误文案(由调用方回给主 isolate)。
  String? slotError(String modelId) =>
      extractors.containsKey(modelId) ? null : '声纹模型未加载:$modelId';

  control.listen((msg) {
    if (msg is BridgeRequest) {
      try {
        switch (msg.kind) {
          case 'load':
            final p = msg.payload as _SpeakerLoadPayload;
            // 先摘掉旧槽再 free:留着已释放对象的引用,一旦重建抛异常,
            // 后续命令就会 use-after-free。摘掉后由 slotError 回友好错误。
            final oldExtractor = extractors.remove(p.modelId);
            final oldManager = managers.remove(p.modelId);
            oldExtractor?.free();
            oldManager?.free();
            final extractor = sherpa_onnx.SpeakerEmbeddingExtractor(
              config: sherpa_onnx.SpeakerEmbeddingExtractorConfig(
                model: p.model,
                numThreads: p.numThreads,
                provider: 'cpu',
              ),
            );
            extractors[p.modelId] = extractor;
            managers[p.modelId] = sherpa_onnx.SpeakerEmbeddingManager(
              extractor.dim,
            );
            mainPort.send(BridgeReply(id: msg.id, payload: true));
          case 'extract':
            final g = msg.payload as _SpeakerExtractPayload;
            final err = slotError(g.modelId);
            if (err != null) {
              mainPort.send(BridgeReply(id: msg.id, error: err));
              break;
            }
            final samples = g.samples is TransferableTypedData
                ? (g.samples as TransferableTypedData)
                    .materialize()
                    .asFloat32List()
                : g.samples as Float32List;
            final stream = extractors[g.modelId]!.createStream();
            stream.acceptWaveform(samples: samples, sampleRate: g.sampleRate);
            final emb = extractors[g.modelId]!.compute(stream);
            stream.free();
            mainPort.send(BridgeReply(id: msg.id, payload: emb));
          case 'add':
            final e = msg.payload as _SpeakerEnrollPayload;
            final err = slotError(e.modelId);
            if (err != null) {
              mainPort.send(BridgeReply(id: msg.id, error: err));
              break;
            }
            mainPort.send(BridgeReply(
              id: msg.id,
              payload: managers[e.modelId]!.addMulti(
                name: e.name,
                embeddingList: e.embeddings,
              ),
            ));
          case 'remove':
            final r = msg.payload as _SpeakerRemovePayload;
            final err = slotError(r.modelId);
            if (err != null) {
              mainPort.send(BridgeReply(id: msg.id, error: err));
              break;
            }
            mainPort.send(BridgeReply(
              id: msg.id,
              payload: managers[r.modelId]!.remove(r.name),
            ));
          case 'search':
            final s = msg.payload as _SpeakerSearchPayload;
            final err = slotError(s.modelId);
            if (err != null) {
              mainPort.send(BridgeReply(id: msg.id, error: err));
              break;
            }
            mainPort.send(BridgeReply(
              id: msg.id,
              payload: managers[s.modelId]!.search(
                embedding: s.embedding,
                threshold: s.threshold,
              ),
            ));
          case 'verify':
            final v = msg.payload as _SpeakerVerifyPayload;
            final err = slotError(v.modelId);
            if (err != null) {
              mainPort.send(BridgeReply(id: msg.id, error: err));
              break;
            }
            mainPort.send(BridgeReply(
              id: msg.id,
              payload: managers[v.modelId]!.verify(
                name: v.name,
                embedding: v.embedding,
                threshold: v.threshold,
              ),
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
