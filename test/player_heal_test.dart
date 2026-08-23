/// SequentialAudioPlayer 自愈能力测试。
///
/// 核心保障:若 audioplayers 的 `onPlayerComplete` 事件丢失(真实设备上
/// 偶发),播放器靠"WAV 时长 + 宽限"看门狗强制推进,不会永久卡死。
///
/// 通过注入 mock 平台接口,让 `AudioPlayer` 在无真实音频设备下可构造;
/// 再用一个"从不发完成事件"的假 `AudioPlayer` 驱动看门狗路径。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_tts_demo/utils/sequential_audio_player.dart';
import 'package:flutter_tts_demo/utils/wav_encoder.dart';

/// 全局平台 mock:init 等返回立即完成的 Future,事件流为空。
class _MockGlobalPlatform extends GlobalAudioplayersPlatformInterface {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == Symbol('getGlobalEventStream')) {
      return const Stream<GlobalAudioEvent>.empty();
    }
    return Future<void>.value();
  }
}

/// 播放器平台 mock:create/play 等返回立即完成的 Future,事件流为空。
class _MockPlayerPlatform extends AudioplayersPlatformInterface {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == Symbol('getEventStream')) {
      return const Stream<AudioEvent>.empty();
    }
    return Future<void>.value();
  }
}

/// 假 AudioPlayer:play/stop 均为 no-op,且**从不发完成事件**。
class _SilentAudioPlayer extends AudioPlayer {
  final _complete = StreamController<void>.broadcast();

  @override
  Stream<void> get onPlayerComplete => _complete.stream;

  @override
  Future<void> play(
    Source source, {
    double? volume,
    double? balance,
    AudioContext? ctx,
    Duration? position,
    PlayerMode? mode,
  }) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('onPlayerComplete 丢失时看门狗强制推进,不永久卡死', () async {
    // 注入 mock 平台,使 AudioPlayer 在测试环境可构造。
    GlobalAudioplayersPlatformInterface.instance = _MockGlobalPlatform();
    AudioplayersPlatformInterface.instance = _MockPlayerPlatform();

    final audio = _SilentAudioPlayer();
    final player = SequentialAudioPlayer(player: audio);
    final started = <int>[];
    var drained = false;
    player.onSegmentStarted = started.add;
    player.onQueueDrained = () => drained = true;
    player.nextSegmentProvider = (i) async {
      if (i >= 2) return null;
      // 极短 WAV(时长≈0),完成看门狗 ≈ 1.5s 宽限。
      return wavBytes(Float32List(1), 16000);
    };

    await player.play();
    // 两段 × ~1.5s 看门狗 ≈ 3s;多留余量。
    await Future<void>.delayed(const Duration(milliseconds: 4000));

    expect(started, [0, 1], reason: '无完成事件时也应靠看门狗推进全部段');
    expect(drained, isTrue, reason: '播放完成后应正常排空');
    await player.dispose();
  });
}
