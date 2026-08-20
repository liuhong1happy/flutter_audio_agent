/// 测试用的假实现:假引擎、假下载器。
///
/// 供单元测试、widget 冒烟测试与 patrol 集成测试共用,避免依赖
/// 真实 sherpa-onnx 模型与真实网络。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter_tts_demo/data/model_downloader.dart';
import 'package:flutter_tts_demo/data/model_files_resolver.dart';
import 'package:flutter_tts_demo/models/tts_model.dart';
import 'package:flutter_tts_demo/models/tts_settings.dart';
import 'package:flutter_tts_demo/tts/sequential_audio_player.dart';
import 'package:flutter_tts_demo/tts/tts_engine.dart';

/// 记录型假引擎:记录每次合成请求,返回短静音音频。
class FakeTtsEngine implements TtsEngine {
  FakeTtsEngine({this.sampleRate = 16000, this.segmentDuration = const Duration(milliseconds: 80)});

  final int sampleRate;
  final Duration segmentDuration;

  final List<String> generatedTexts = [];
  final List<int> generatedSids = [];
  final List<double> generatedSpeeds = [];
  bool _isLoaded = false;

  @override
  bool get isLoaded => _isLoaded;

  @override
  Future<void> load({
    required ResolvedModelPaths paths,
    required TtsModel model,
    required TtsSettings settings,
  }) async {
    _isLoaded = true;
  }

  @override
  Future<GeneratedAudioData> generate({
    required String text,
    required int sid,
    required double speed,
  }) async {
    generatedTexts.add(text);
    generatedSids.add(sid);
    generatedSpeeds.add(speed);
    await Future<void>.delayed(segmentDuration);
    final n = (sampleRate * segmentDuration.inMilliseconds / 1000).round();
    return GeneratedAudioData(
      samples: Float32List(n),
      sampleRate: sampleRate,
    );
  }

  @override
  void dispose() {
    _isLoaded = false;
  }
}

/// 假顺序播放器:不触碰真实音频设备,用计时器模拟逐段播放,
/// 驱动 onSegmentStarted / onQueueDrained 回调。
class FakeAudioPlaybackQueue implements AudioPlaybackQueue {
  FakeAudioPlaybackQueue({
    this.delayPerSegment = const Duration(milliseconds: 40),
  });

  final Duration delayPerSegment;

  /// 已入队的片段下标(按入队顺序)。
  final List<int> enqueuedSegmentIndexes = [];

  /// 已开始"播放"的片段下标。
  final List<int> startedSegmentIndexes = [];

  int _head = 0;
  bool _timerActive = false;
  bool _paused = false;
  Timer? _currentTimer;
  int pauseCount = 0;
  int resumeCount = 0;

  @override
  void Function(int segmentIndex)? onSegmentStarted;

  @override
  void Function()? onQueueDrained;

  /// 取消挂起的定时器,避免测试结束时 "pending timer"。
  void _cancelTimer() {
    _currentTimer?.cancel();
    _currentTimer = null;
    _timerActive = false;
  }

  @override
  void enqueue({required int segmentIndex, required Uint8List wavBytes}) {
    enqueuedSegmentIndexes.add(segmentIndex);
    if (!_timerActive) _pump();
  }

  void _pump() {
    if (_head >= enqueuedSegmentIndexes.length) {
      _timerActive = false;
      return;
    }
    _timerActive = true;
    _currentTimer = Timer(delayPerSegment, () {
      if (_paused) {
        _timerActive = false;
        return;
      }
      startedSegmentIndexes.add(enqueuedSegmentIndexes[_head]);
      onSegmentStarted?.call(enqueuedSegmentIndexes[_head]);
      _head++;
      if (_head >= enqueuedSegmentIndexes.length) {
        // 最后一段:再"播放"一个时长后 drain,让词高亮有机会推进。
        _timerActive = true;
        _currentTimer = Timer(delayPerSegment, () {
          _timerActive = false;
          onQueueDrained?.call();
        });
      } else {
        _pump();
      }
    });
  }

  @override
  Future<void> pause() async {
    _paused = true;
    pauseCount++;
  }

  @override
  Future<void> resume() async {
    _paused = false;
    resumeCount++;
    if (!_timerActive) _pump();
  }

  @override
  Future<void> stop() async {
    _cancelTimer();
    _head = enqueuedSegmentIndexes.length;
    _paused = false;
  }

  @override
  Future<void> dispose() async {
    await stop();
  }
}

/// 假下载器:在 [savePath] 写一个迷你 tar.bz2(内含占位模型文件),
/// 使完整的"下载 → 解压 → 就绪"链路可在测试中跑通。
class FakeModelDownloader implements ModelDownloader {
  FakeModelDownloader({this.delay});

  final Duration? delay;
  final List<String> downloadedUrls = [];

  @override
  Future<void> download({
    required String url,
    required String savePath,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    downloadedUrls.add(url);
    if (delay != null) await Future<void>.delayed(delay!);
    if (cancelToken?.isCancelled ?? false) return;
    onProgress?.call(0, 100);

    final bytes = buildFakeModelArchive();
    final file = File(savePath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);

    onProgress?.call(100, 100);
  }
}

/// 构造一个内含占位模型文件的 tar.bz2。
Uint8List buildFakeModelArchive() {
  const base = 'vits-piper-zh_CN-xiao_ya-medium-int8';
  final archive = Archive();
  archive.addFile(ArchiveFile.string('$base/model.onnx', ''));
  archive.addFile(ArchiveFile.string('$base/tokens.txt', ''));
  archive.addFile(ArchiveFile.string('$base/lexicon.txt', ''));
  archive.addFile(ArchiveFile.string('$base/number.fst', ''));
  final tar = TarEncoder().encodeBytes(archive);
  return BZip2Encoder().encodeBytes(tar);
}
