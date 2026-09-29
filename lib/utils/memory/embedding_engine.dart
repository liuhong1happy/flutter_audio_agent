/// 本地文本向量化引擎(`flutter_embedder` + `bge-small-zh-v1.5`)。
///
/// 实现要点与已实测的事实(全部在 Android 17 / x86_64 模拟器上验证过):
///
/// 1. **不需要 `onnxruntime-android`**。`flutter_embedder` 的 Rust 侧用 `ort` crate 的
///    `load-dynamic`,**运行时 `dlopen` 名为 `libonnxruntime.so` 的库** —— 而 sherpa
///    已经把这一份打进 APK 了。这绕开了本版最大的架构障碍:sherpa 与该插件各自携带的
///    `libonnxruntime.so` **同 soname、但符号版本节点不同**(`VERS_1.27.1` vs
///    `VERS_1.23.0`),不可能在同一 APK 内存活两份(详见 TODO.md 坑 19)。
///    ⚠️ 这构成**隐式耦合**:哪天 sherpa 改了库名或不再打包它,这里会在**运行时**才失败
///    ⇒ 需要启动自检(见 [FlutterEmbedderEngine.load] 的成功/失败上报)。
///
/// 2. **必须跑在后台 isolate**。`BgeEmbedder.embed()` 是**同步 FFI**(返回
///    `List<Float32List>`,不是 `Future`),会**阻塞所在 isolate**:实测单条 128ms、
///    16 条 1288ms,而索引一个知识库要几百上千条 ⇒ 放 UI isolate 上就是卡死/ANR。
///    故这里复用仓库既有的 [IsolateBridge],把整个嵌入会话关在 worker isolate 内。
///
/// 3. **插件不会替我们截断**。输入超过模型 `max_position_embeddings`(512 token)时
///    ORT 会在 Add 节点报 `Attempting to broadcast an axis by a dimension other than 1.
///    512 by N`。这是**响亮失败**(好过静默丢内容),但调用方**必须自己切块** ——
///    由 [KbChunker] 的 500 预算守住(且它以字符数当 token 数上界,中文约 1:1,永不越界)。
///
/// 4. 池化由插件内部完成:**CLS 池化**(取第 0 行)+ L2 归一化 —— 正是
///    `bge-small-zh-v1.5` 的 `1_Pooling/config.json` 所要求的。
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_embedder/flutter_embedder.dart';

import 'package:flutter_tts_demo/utils/isolate_bridge.dart';

/// 向量维度。`bge-small-zh-v1.5` 的 `hidden_size`。
const int kEmbeddingDim = 512;

/// APK 内 ORT 动态库名(**由 sherpa 提供**)。
const String kOrtLibraryName = 'libonnxruntime.so';

/// 一次向量化的耗时分解(真机调参与回归用)。
class EmbeddingTiming {
  const EmbeddingTiming({required this.textCount, required this.elapsedMs});

  final int textCount;
  final int elapsedMs;

  /// 均摊耗时(毫秒/条)。
  double get perTextMs => textCount == 0 ? 0 : elapsedMs / textCount;

  @override
  String toString() =>
      'EmbeddingTiming(n=$textCount, ${elapsedMs}ms, ${perTextMs.toStringAsFixed(1)}ms/条)';
}

/// 文本向量化引擎接口(便于测试注入假实现)。
abstract class EmbeddingEngine {
  bool get isLoaded;

  /// 最近一次 [embed] 的耗时;未跑过为 null。
  EmbeddingTiming? get lastTiming;

  /// 加载模型与分词器(幂等)。
  ///
  /// 失败时抛错 —— **不要静默降级**:嵌入不可用时上层应明确"检索不可用"而不是
  /// 假装检索过。
  Future<void> load({
    required String modelPath,
    required String tokenizerPath,
  });

  /// 批量向量化,返回与入参等长的**单位向量**(L2 归一化后的 512 维)。
  ///
  /// ⚠️ 每条文本必须短于 512 token(见文件头第 3 点)。
  Future<List<Float32List>> embed(List<String> texts);

  /// 卸载并释放隔离区(嵌入会话常驻内存不小,空闲时应释放)。
  Future<void> unload();
}

/// 后台 worker:整个嵌入会话都关在这里。
///
/// 必须是顶层函数(`Isolate.spawn` 的要求),且**不得**捕获外部状态。
void _embeddingWorkerEntry(SendPort mainPort) {
  final receive = ReceivePort();
  // 握手:先把自己的 port 回发给 main。
  mainPort.send(receive.sendPort);

  BgeEmbedder? embedder;

  receive.listen((Object? msg) async {
    if (msg is! BridgeRequest) return;
    try {
      switch (msg.kind) {
        case 'load':
          final p = (msg.payload as Map).cast<String, Object?>();
          // 先打开 APK 内的 ORT 动态库(sherpa 提供),再交给 Rust 侧按路径加载。
          await initFlutterEmbedder(path: kOrtLibraryName);
          embedder = BgeEmbedder.create(
            modelPath: p['modelPath']! as String,
            tokenizerPath: p['tokenizerPath']! as String,
          );
          mainPort.send(BridgeReply(id: msg.id));
        case 'embed':
          final texts = (msg.payload! as List).cast<String>();
          if (embedder == null) {
            throw StateError('嵌入引擎未加载');
          }
          // 同步 FFI:阻塞的是本 worker isolate,不是 UI。
          final vecs = embedder!.embed(texts: texts);
          mainPort.send(BridgeReply(id: msg.id, payload: vecs));
        case 'unload':
          embedder?.dispose();
          embedder = null;
          mainPort.send(BridgeReply(id: msg.id));
        default:
          throw StateError('未知的嵌入请求: ${msg.kind}');
      }
    } catch (e) {
      mainPort.send(BridgeReply(id: msg.id, error: '$e'));
    }
  });
}

/// 基于 `flutter_embedder` + 后台 isolate 的实现。
class FlutterEmbedderEngine implements EmbeddingEngine {
  FlutterEmbedderEngine();

  IsolateBridge? _bridge;
  bool _loaded = false;
  EmbeddingTiming? _lastTiming;

  @override
  bool get isLoaded => _loaded;

  @override
  EmbeddingTiming? get lastTiming => _lastTiming;

  /// worker 启动 + 加载模型。失败即抛错(不静默降级)。
  @override
  Future<void> load({
    required String modelPath,
    required String tokenizerPath,
  }) async {
    if (_loaded) return;
    final bridge = IsolateBridge(_embeddingWorkerEntry, debugName: 'embedding');
    _bridge = bridge;
    try {
      await bridge.request('load', {
        'modelPath': modelPath,
        'tokenizerPath': tokenizerPath,
      });
    } catch (e) {
      // 失败时把 isolate 收掉,避免留下半死不活的 worker。
      bridge.dispose();
      _bridge = null;
      rethrow;
    }
    _loaded = true;
  }

  @override
  Future<List<Float32List>> embed(List<String> texts) async {
    if (texts.isEmpty) return const [];
    final bridge = _bridge;
    if (bridge == null || !_loaded) {
      throw StateError('嵌入引擎未加载,先调 load()');
    }
    final sw = Stopwatch()..start();
    final raw = await bridge.request('embed', texts);
    sw.stop();
    final vecs = (raw! as List).cast<Float32List>();
    _lastTiming = EmbeddingTiming(
      textCount: texts.length,
      elapsedMs: sw.elapsedMilliseconds,
    );
    return vecs;
  }

  @override
  Future<void> unload() async {
    final bridge = _bridge;
    _bridge = null;
    _loaded = false;
    if (bridge == null) return;
    try {
      await bridge.request('unload', null);
    } catch (_) {
      // 卸载失败无所谓,下面直接杀 isolate。
    }
    bridge.dispose();
  }
}
