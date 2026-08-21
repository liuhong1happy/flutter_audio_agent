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

/// 假顺序播放器:不触碰真实音频设备,拉取式逐段模拟播放,
/// 驱动 onSegmentStarted / onQueueDrained 回调。
class FakeAudioPlaybackQueue implements AudioPlaybackQueue {
  FakeAudioPlaybackQueue({
    this.delayPerSegment = const Duration(milliseconds: 40),
  });

  final Duration delayPerSegment;

  /// 已开始"播放"的片段下标(按播放顺序)。
  final List<int> startedSegmentIndexes = [];

  int _nextIndex = 0;
  bool _running = false;
  bool _paused = false;
  bool _stopped = true;
  Future<void>? _activeDrive;

  /// 会话代数:每次 play/stop 递增,旧 drive 检测到代数变化即退出,
  /// 避免旧 drive 误用新会话的 _running/_stopped 状态。
  int _generation = 0;
  int pauseCount = 0;
  int resumeCount = 0;

  @override
  void Function(int segmentIndex)? onSegmentStarted;

  @override
  void Function()? onQueueDrained;

  @override
  Future<Uint8List?> Function(int segmentIndex)? nextSegmentProvider;

  @override
  Future<void> play() async {
    final gen = ++_generation;
    // 等上一次 drive 完全退出,避免旧 drive 误用新会话状态。
    if (_activeDrive != null) {
      try {
        await _activeDrive;
      } catch (_) {}
    }
    if (gen != _generation) return; // 等待期间又被 stop/play 取代。
    _stopped = false;
    _paused = false;
    _running = true;
    _nextIndex = 0;
    _activeDrive = _drive(gen);
    unawaited(_activeDrive!);
  }

  Future<void> _drive(int gen) async {
    try {
      while (_running && !_stopped) {
        if (gen != _generation) return; // 已被新会话取代。
        // 暂停时挂起(保留进度),恢复后继续。
        if (_paused) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          continue;
        }
        final provider = nextSegmentProvider;
        if (provider == null) break;
        final idx = _nextIndex;
        final wav = await provider(idx);
        if (gen != _generation) return;
        if (!_running || _stopped) return;
        if (wav == null) break;
        startedSegmentIndexes.add(idx);
        onSegmentStarted?.call(idx);
        _nextIndex = idx + 1;
        // 模拟该段播放时长。
        await Future<void>.delayed(delayPerSegment);
      }
      if (gen == _generation && !_stopped && !_paused) {
        _running = false;
        onQueueDrained?.call();
      }
    } catch (_) {
      // 忽略 provider 异常;真实播放器会由 provider 自行捕获。
    }
  }

  @override
  Future<void> pause() async {
    _paused = true;
    pauseCount++;
  }

  @override
  Future<void> resume() async {
    if (!_paused) return;
    _paused = false;
    resumeCount++;
  }

  @override
  Future<void> stop() async {
    _generation++;
    _stopped = true;
    _paused = false;
    _running = false;
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
///
/// `model.onnx` 写入 4096 字节,使"主模型非平凡大小"校验在测试中可通过。
Uint8List buildFakeModelArchive() {
  const base = 'vits-piper-zh_CN-xiao_ya-medium-int8';
  final archive = Archive();
  final onnxBytes = List<int>.filled(4096, 7);
  archive.addFile(ArchiveFile('$base/model.onnx', onnxBytes.length, onnxBytes));
  archive.addFile(ArchiveFile.string('$base/tokens.txt', ''));
  archive.addFile(ArchiveFile.string('$base/lexicon.txt', ''));
  archive.addFile(ArchiveFile.string('$base/number.fst', ''));
  final tar = TarEncoder().encodeBytes(archive);
  return BZip2Encoder().encodeBytes(tar);
}
