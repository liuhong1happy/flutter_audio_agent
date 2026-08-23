/// 后台 isolate 通信桥。
///
/// 把"spawn isolate → 握手 → 请求/应答 → 单向 fire-and-forget →
/// worker→main 事件通道"这套通用协议抽出来,供多个 sherpa 引擎
/// (TTS / VAD / ASR / 声纹 / PocketTTS)复用,避免每个引擎重复实现
/// id 映射 + Completer + TransferableTypedData 交接逻辑。
///
/// 协议(消息均为 SendPort 可序列化的轻量对象):
/// - worker 启动后先发回自己的 [SendPort] 完成握手。
/// - main→worker 请求:[BridgeRequest{id, kind, payload}],worker 以
///   [BridgeReply{id, payload, error}] 应答(完成对应 [Completer])。
/// - main→worker 单向:[BridgeFire{kind, payload}],无应答(VAD 持续喂样本)。
/// - worker→main 事件:[BridgeEvent{kind, payload}],经 [events] 流广播
///   (VAD 段回调)。
///
/// 音频样本跨 isolate 一律用 `TransferableTypedData` 零拷贝。
library;

import 'dart:async';
import 'dart:isolate';

/// 后台 isolate 入口签名:收到 main 的 [SendPort],先 initBindings,
/// 再建 ReceivePort 并回发其 sendPort 完成握手。
typedef IsolateWorkerEntry = void Function(SendPort mainPort);

/// main → worker:带 id 的请求(worker 应回复 [BridgeReply])。
class BridgeRequest {
  const BridgeRequest({required this.id, required this.kind, required this.payload});
  final int id;
  final String kind;
  final Object? payload;
}

/// worker → main:对 [BridgeRequest] 的应答。
class BridgeReply {
  const BridgeReply({required this.id, this.payload, this.error});
  final int id;
  final Object? payload;
  final String? error;
}

/// main → worker:单向消息,无需应答。
class BridgeFire {
  const BridgeFire({required this.kind, required this.payload});
  final String kind;
  final Object? payload;
}

/// worker → main:异步事件(经 [IsolateBridge.events] 广播)。
class BridgeEvent {
  const BridgeEvent({required this.kind, required this.payload});
  final String kind;
  final Object? payload;
}

class IsolateBridge {
  IsolateBridge(this._entry, {this.debugName});

  final IsolateWorkerEntry _entry;
  final String? debugName;

  Isolate? _isolate;
  ReceivePort? _replies;
  SendPort? _workerPort;
  Completer<SendPort>? _portCompleter;
  int _nextId = 0;
  final Map<int, Completer<Object?>> _pending = {};

  final StreamController<Object?> _events =
      StreamController<Object?>.broadcast();

  /// worker→main 事件流(如 VAD 段)。
  Stream<Object?> get events => _events.stream;

  bool _disposed = false;

  /// 确保 isolate 已 spawn 并完成握手(幂等)。
  Future<void> ensureStarted() async {
    if (_disposed) throw StateError('IsolateBridge 已释放');
    if (_workerPort != null) return;
    _replies = ReceivePort();
    _portCompleter = Completer<SendPort>();
    _replies!.listen(_onData, onError: (_) {}, onDone: _onDone);
    _isolate = await Isolate.spawn(_entry, _replies!.sendPort,
        debugName: debugName);
    _workerPort = await _portCompleter!.future;
  }

  void _onData(Object? msg) {
    if (msg is SendPort) {
      _portCompleter?.complete(msg);
      return;
    }
    if (msg is BridgeReply) {
      final completer = _pending.remove(msg.id);
      if (completer == null) return;
      if (msg.error != null) {
        completer.completeError(StateError(msg.error!));
      } else {
        completer.complete(msg.payload);
      }
      return;
    }
    if (msg is BridgeEvent) {
      if (!_events.isClosed) _events.add(msg.payload);
      return;
    }
  }

  void _onDone() {
    _workerPort = null;
  }

  /// 请求/应答(worker 未启动则先启动)。
  Future<Object?> request(String kind, Object? payload) async {
    await ensureStarted();
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _workerPort!.send(BridgeRequest(id: id, kind: kind, payload: payload));
    return completer.future;
  }

  /// 单向 fire-and-forget(不等待应答)。
  Future<void> fire(String kind, Object? payload) async {
    await ensureStarted();
    _workerPort!.send(BridgeFire(kind: kind, payload: payload));
  }

  /// 释放 isolate 与所有在途请求(以错误收尾)。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _workerPort = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('引擎已释放'));
    }
    _pending.clear();
    _events.close();
    _replies?.close();
    _replies = null;
  }
}
