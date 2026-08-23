/// 基于 audioplayers 的顺序播放器(拉取式)。
///
/// 把多个 WAV 片段按序播放。**拉取式**设计:播放器在需要时通过
/// [nextSegmentProvider] 向调用方索取下一段的 WAV 字节,一次最多预取 1 段,
/// 避免长文本下"急切合成 + 无界队列"导致的主 isolate 过载与内存无界增长。
///
/// 自愈保障:
/// - 每段 `play()` 有加载超时,`onPlayerComplete` 丢失时由"完成看门狗"
///   按"WAV 时长 + 宽限"强制推进,任何单点卡死都不会永久阻塞。
/// - provider 有合成超时,`stop()` 会立即打断 pump 对慢合成的等待。
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// 顺序播放队列接口(便于测试注入假实现)。
abstract class AudioPlaybackQueue {
  /// 某段开始播放时回调(参数为该段在片段列表中的下标)。
  void Function(int segmentIndex)? onSegmentStarted;

  /// 队列全部播放完毕(provider 返回 null 且最后一段播完)。
  void Function()? onQueueDrained;

  /// 拉取式源:返回 [segmentIndex] 的 WAV 字节;`null` 表示没有更多段。
  ///
  /// 播放器会在需要时调用(播放当前段期间预取下一段)。
  Future<Uint8List?> Function(int segmentIndex)? nextSegmentProvider;

  /// 从第 0 段开始拉取并播放(内部异步推进,立即返回)。
  Future<void> play();

  /// 暂停播放(保留进度,继续播放从当前位置恢复)。
  Future<void> pause();

  /// 继续播放。
  Future<void> resume();

  /// 停止并复位。
  Future<void> stop();

  Future<void> dispose();
}

class SequentialAudioPlayer implements AudioPlaybackQueue {
  SequentialAudioPlayer({AudioPlayer? player})
      : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  /// 加载源超时(audioplayers 等 `onPrepared` 事件)。
  static const Duration _loadTimeout = Duration(seconds: 15);

  /// 单段合成超时(防 worker/引擎挂死导致整条管线卡住)。
  static const Duration _providerTimeout = Duration(minutes: 2);

  /// 完成事件丢失时的宽限期(WAV 实际时长之外再等这么久)。
  static const Duration _completionGrace = Duration(milliseconds: 1500);

  /// 忽略"段开始后 80ms 内"的完成事件(上一段的陈旧延迟事件)。
  static const Duration _staleCompleteGuard = Duration(milliseconds: 80);

  static final Object _haltSentinel = Object();
  static final Object _nullSentinel = Object();

  bool _initialized = false;
  bool _pumpRunning = false;
  bool _paused = false;
  bool _stopped = true;

  /// 当前泵的 Future(play/stop 时等待旧泵完全退出,避免并发/状态竞争)。
  Future<void>? _pumpFuture;

  /// 下一个要请求的片段下标。
  int _nextIndex = 0;

  /// 当前正在播放的段 WAV(供暂停后重新武装看门狗)。
  Uint8List? _currentWav;

  /// 当前段完成信号(由 onPlayerComplete 或完成看门狗触发)。
  Completer<void>? _segmentDone;

  /// 完成看门狗。
  Timer? _watchdog;

  /// 停止信号:打断 pump 对慢 provider 的等待。
  Completer<void>? _haltSignal;

  /// 当前段开始播放的时刻。
  DateTime _segmentStartAt = DateTime.fromMillisecondsSinceEpoch(0);

  StreamSubscription<void>? _subscription;

  @override
  void Function(int segmentIndex)? onSegmentStarted;

  @override
  void Function()? onQueueDrained;

  @override
  Future<Uint8List?> Function(int segmentIndex)? nextSegmentProvider;

  void init() {
    if (_initialized) return;
    _initialized = true;
    _subscription = _player.onPlayerComplete.listen((_) => _onComplete());
  }

  /// 从第 0 段开始拉取并播放。
  @override
  Future<void> play() async {
    init();
    if (_pumpRunning || !_stopped) {
      await stop();
      // 等旧泵完全退出,避免其 finally 把新泵的 _pumpRunning 误清。
      if (_pumpFuture != null) {
        try {
          await _pumpFuture;
        } catch (_) {}
      }
    }
    _stopped = false;
    _paused = false;
    _nextIndex = 0;
    _currentWav = null;
    _haltSignal = Completer<void>();
    _pumpRunning = true;
    _pumpFuture = _pump();
    unawaited(_pumpFuture!);
  }

  /// 泵:顺序"取段 → 播放 → 等待完成",播放期间预取下一段。
  ///
  /// 暂停时泵**挂起等待**而非退出,从而保留局部进度;恢复播放后从
  /// 断点继续,不会重播。
  Future<void> _pump() async {
    Uint8List? buffered; // 已预取、待播放的下一段。
    try {
      while (true) {
        if (_stopped) return;

        // 暂停时挂起,直到恢复或停止(保留局部状态)。
        while (_paused) {
          await Future<void>.delayed(const Duration(milliseconds: 60));
          if (_stopped) return;
        }

        // 1. 拿到当前段(优先用预取结果)。
        Uint8List? wav = buffered;
        buffered = null;
        if (wav == null) {
          wav = await _fetch(_nextIndex);
          if (_stopped) return;
          if (wav == null) break;
          if (_paused) {
            buffered = wav; // 取段完成时刚好暂停,保留该段。
            continue;
          }
        }

        // 2. 开始播放。
        final idx = _nextIndex;
        _nextIndex = idx + 1;
        onSegmentStarted?.call(idx);
        _segmentStartAt = DateTime.now();
        try {
          await _player.stop();
          await _player
              .play(BytesSource(wav, mimeType: 'audio/wav'))
              .timeout(_loadTimeout);
        } catch (e) {
          debugPrint('音频播放失败(第 $idx 段): $e');
          // 中止可能还在后台加载的源,避免其迟到的完成事件污染下一段。
          try {
            await _player.stop();
          } catch (_) {}
        }
        if (_stopped) return;

        // 3. 并行预取下一段 + 等待本段播完。
        final nextIdx = idx + 1;
        final prefetch = _fetch(nextIdx);
        await _waitForSegmentDone(wav);
        if (_stopped) return;
        if (_paused) continue; // 过渡时刻暂停,回挂起;预取结果下次取。

        // 4. 推进到下一段。
        final resolved = await _haltAware(prefetch);
        if (_stopped) return;
        if (_paused) {
          buffered = resolved; // 暂停,保留预取结果。
          continue;
        }
        if (resolved == null) break;
        buffered = resolved;
      }
      if (!_stopped && !_paused) {
        onQueueDrained?.call();
      }
    } finally {
      _pumpRunning = false;
    }
  }

  /// 拉取一段 WAV(带合成超时 + 可被 stop 打断)。
  Future<Uint8List?> _fetch(int idx) {
    final provider = nextSegmentProvider;
    if (provider == null) return Future.value(null);
    final withTimeout = provider(idx).timeout(
      _providerTimeout,
      onTimeout: () {
        debugPrint('第 $idx 段合成超时,跳过');
        return null;
      },
    );
    return _haltAware(withTimeout);
  }

  /// 与停止信号赛跑:被 [stop] 打断时返回 null。
  Future<Uint8List?> _haltAware(Future<Uint8List?> future) async {
    final halt = _haltSignal?.future;
    if (halt == null) return future;
    final r = await Future.any<Object?>([
      future.then<Object?>((v) => v ?? _nullSentinel),
      halt.then<Object?>((_) => _haltSentinel),
    ]);
    if (identical(r, _haltSentinel) || identical(r, _nullSentinel)) return null;
    return r as Uint8List;
  }

  /// 等待当前段播完;`onPlayerComplete` 丢失时由看门狗强制推进。
  Future<void> _waitForSegmentDone(Uint8List wav) async {
    _currentWav = wav;
    final done = Completer<void>();
    _segmentDone = done;
    _armWatchdog(wav);
    try {
      await done.future;
    } finally {
      _watchdog?.cancel();
      _watchdog = null;
      _segmentDone = null;
      _currentWav = null;
    }
  }

  void _armWatchdog(Uint8List wav) {
    final seconds = _estimateWavSeconds(wav);
    final duration = Duration(milliseconds: (seconds * 1000).round());
    _watchdog?.cancel();
    _watchdog = Timer(duration + _completionGrace, () {
      debugPrint('完成事件丢失,看门狗强制推进');
      _segmentDone?.complete();
    });
  }

  /// 从 WAV 头解析时长(固定 16bit 单声道 PCM,见 [wavBytes])。
  static double _estimateWavSeconds(Uint8List wav) {
    try {
      if (wav.length < 44) return 0;
      int u32(int o) =>
          wav[o] | (wav[o + 1] << 8) | (wav[o + 2] << 16) | (wav[o + 3] << 24);
      final byteRate = u32(28);
      final dataSize = u32(40);
      if (byteRate <= 0) return 0;
      return dataSize / byteRate;
    } catch (_) {
      return 0;
    }
  }

  void _onComplete() {
    if (_paused || _stopped) return;
    // 忽略"刚开播 80ms 内"的完成事件(上一段的陈旧延迟事件)。
    if (DateTime.now().difference(_segmentStartAt) < _staleCompleteGuard) {
      return;
    }
    _watchdog?.cancel();
    _watchdog = null;
    final d = _segmentDone;
    _segmentDone = null;
    d?.complete();
  }

  @override
  Future<void> pause() async {
    if (_stopped) return;
    _paused = true;
    _watchdog?.cancel();
    await _player.pause();
  }

  @override
  Future<void> resume() async {
    if (!_paused) return;
    _paused = false;
    await _player.resume();
    // 中途暂停:重新武装当前段的完成看门狗(泵仍在等待完成信号)。
    if (_segmentDone != null && _currentWav != null) {
      _armWatchdog(_currentWav!);
    }
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    _paused = false;
    _watchdog?.cancel();
    _watchdog = null;
    final d = _segmentDone;
    _segmentDone = null;
    d?.complete();
    _haltSignal?.complete();
    _haltSignal = null;
    await _player.stop();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _subscription?.cancel();
    await _player.dispose();
  }
}
