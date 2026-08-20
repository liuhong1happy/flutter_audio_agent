/// 基于 audioplayers 的顺序播放器。
///
/// 把多个 WAV 片段排队按序播放;每个片段开始播放时回调
/// [onSegmentStarted],队列播空时回调 [onQueueDrained]。
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// 顺序播放队列接口(便于测试注入假实现)。
abstract class AudioPlaybackQueue {
  /// 某段开始播放时回调(参数为该段在片段列表中的下标)。
  void Function(int segmentIndex)? onSegmentStarted;

  /// 队列全部播放完毕。
  void Function()? onQueueDrained;

  /// 入队一段 WAV 音频。
  void enqueue({required int segmentIndex, required Uint8List wavBytes});

  /// 暂停播放(保留队列与进度)。
  Future<void> pause();

  /// 继续播放。
  Future<void> resume();

  Future<void> stop();

  Future<void> dispose();
}

class SequentialAudioPlayer implements AudioPlaybackQueue {
  SequentialAudioPlayer({AudioPlayer? player})
      : _player = player ?? AudioPlayer();

  final AudioPlayer _player;
  final List<_QueuedAudio> _queue = [];
  bool _playing = false;
  bool _paused = false;
  StreamSubscription<void>? _subscription;
  bool _initialized = false;

  /// 某段开始播放时回调(参数为该段在片段列表中的下标)。
  @override
  void Function(int segmentIndex)? onSegmentStarted;

  /// 队列全部播放完毕。
  @override
  void Function()? onQueueDrained;

  void init() {
    if (_initialized) return;
    _initialized = true;
    _subscription = _player.onPlayerComplete.listen((_) => _onComplete());
  }

  /// 入队一段 WAV 音频。
  @override
  void enqueue({required int segmentIndex, required Uint8List wavBytes}) {
    init();
    _queue.add(_QueuedAudio(segmentIndex: segmentIndex, bytes: wavBytes));
    if (!_playing && !_paused) {
      _playNext();
    }
  }

  @override
  Future<void> pause() async {
    _paused = true;
    await _player.pause();
  }

  @override
  Future<void> resume() async {
    _paused = false;
    await _player.resume();
    if (!_playing && _queue.isNotEmpty) {
      _playNext();
    }
  }

  Future<void> _playNext() async {
    if (_queue.isEmpty) {
      _playing = false;
      onQueueDrained?.call();
      return;
    }
    final item = _queue.removeAt(0);
    _playing = true;
    onSegmentStarted?.call(item.segmentIndex);
    try {
      await _player.stop();
      await _player.play(
        BytesSource(item.bytes, mimeType: 'audio/wav'),
      );
    } catch (e) {
      debugPrint('音频播放失败: $e');
      // 播放失败也继续推进,避免卡死。
      _playing = false;
      _playNext();
    }
  }

  void _onComplete() {
    _playing = false;
    if (_paused) return; // 暂停时不推进下一段。
    _playNext();
  }

  /// 停止并清空队列。
  @override
  Future<void> stop() async {
    _queue.clear();
    _playing = false;
    await _player.stop();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _subscription?.cancel();
    await _player.dispose();
  }
}

class _QueuedAudio {
  const _QueuedAudio({required this.segmentIndex, required this.bytes});
  final int segmentIndex;
  final Uint8List bytes;
}
