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
import 'package:flutter_tts_demo/utils/app_lock_service.dart';
import 'package:flutter_tts_demo/utils/mic_recorder.dart';
import 'package:flutter_tts_demo/data/models/conversation_message.dart';
import 'package:flutter_tts_demo/data/conversation_store.dart';
import 'package:flutter_tts_demo/data/model_downloader.dart';
import 'package:flutter_tts_demo/data/model_files_resolver.dart';
import 'package:flutter_tts_demo/utils/llm_client.dart';
import 'package:flutter_tts_demo/data/models/tts_model.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/utils/engines/asr_engine.dart';
import 'package:flutter_tts_demo/utils/engines/pocket_tts_engine.dart';
import 'package:flutter_tts_demo/utils/sequential_audio_player.dart';
import 'package:flutter_tts_demo/utils/engines/speaker_engine.dart';
import 'package:flutter_tts_demo/utils/engines/tts_engine.dart';
import 'package:flutter_tts_demo/utils/engines/vad_engine.dart';

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

    final file = File(savePath);
    await file.parent.create(recursive: true);
    // 裸文件(rawFile,URL 以 .onnx 结尾)写一段足够大的原始字节;
    // tar.bz2 模型写内含占位模型文件的归档。
    if (url.endsWith('.onnx')) {
      await file.writeAsBytes(List<int>.generate(2048, (i) => i % 251));
    } else {
      await file.writeAsBytes(buildFakeModelArchive());
    }

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

/// 假麦克风:不触碰真实录音平台,可编程地吐出 PCM16 字节流。
class FakeMicRecorder implements MicRecorder {
  FakeMicRecorder({this.permissionGranted = true});

  bool permissionGranted;
  int startStreamCalls = 0;
  final List<String> recordedPaths = [];
  final StreamController<Uint8List> _controller =
      StreamController<Uint8List>.broadcast();

  /// 模拟设备吐出 PCM16 字节。
  void emitPcm(Uint8List bytes) => _controller.add(bytes);

  @override
  Future<bool> hasPermission({bool request = true}) async => permissionGranted;

  @override
  Future<Stream<Uint8List>> startStream({int sampleRate = 16000}) async {
    startStreamCalls++;
    return _controller.stream;
  }

  @override
  Future<void> stopStream() async {}

  @override
  Future<void> start({required String path, required int sampleRate}) async {
    recordedPaths.add(path);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

/// 假 ASR 引擎:识别返回预设文本。
class FakeAsrEngine extends AsrEngine {
  String nextText = '';

  /// recognize 调用次数(用来断言"门禁拒绝时根本没跑 ASR")。
  int recognizeCalls = 0;

  @override
  bool get isLoaded => true;

  @override
  Future<void> load({
    required String kind,
    required String modelPath,
    required String tokensPath,
    int numThreads = 2,
  }) async {}

  @override
  Future<AsrResult> recognize(Float32List samples, int sampleRate) async {
    recognizeCalls++;
    return AsrResult(text: nextText);
  }

  @override
  void dispose() {}
}

/// 假声纹引擎:识别返回预设名字,并记录按模型分桶的调用。
///
/// `nextName` 是模型无关的兜底(老测试只设它);`nextNameByModel` 可按模型
/// 覆盖,用来断言"两个模型互不串"。
class FakeSpeakerEngine extends SpeakerEngine {
  String nextName = '';
  final Map<String, String> nextNameByModel = {};

  /// load 调用序列(断言切模型/重同步)。
  final List<String> loadCalls = [];

  /// modelId → 已注册的名字列表(addMulti 调用记录)。
  final Map<String, List<String>> addedByModel = {};

  /// modelId → 已删除的名字列表。
  final Map<String, List<String>> removedByModel = {};

  @override
  bool get isLoaded => loadCalls.isNotEmpty;

  @override
  bool isModelLoaded(String modelId) =>
      loadCalls.isNotEmpty && loadCalls.last == modelId;

  @override
  Set<String> get loadedModelIds => loadCalls.toSet();

  @override
  Future<void> load({
    required String modelId,
    required String modelPath,
    int numThreads = 1,
  }) async {
    loadCalls.add(modelId);
  }

  @override
  Future<Float32List> extract({
    required String modelId,
    required Float32List samples,
    required int sampleRate,
  }) async =>
      Float32List(192);

  @override
  Future<bool> add({
    required String modelId,
    required String name,
    required Float32List embedding,
  }) async =>
      addMulti(modelId: modelId, name: name, embeddings: [embedding]);

  @override
  Future<bool> addMulti({
    required String modelId,
    required String name,
    required List<Float32List> embeddings,
  }) async {
    addedByModel.putIfAbsent(modelId, () => []).add(name);
    return true;
  }

  @override
  Future<bool> remove({required String modelId, required String name}) async {
    removedByModel.putIfAbsent(modelId, () => []).add(name);
    return true;
  }

  @override
  Future<String> search({
    required String modelId,
    required Float32List embedding,
    required double threshold,
  }) async =>
      nextNameByModel[modelId] ?? nextName;

  @override
  Future<bool> verify({
    required String modelId,
    required String name,
    required Float32List embedding,
    required double threshold,
  }) async =>
      true;

  @override
  void dispose() {}
}

/// 假设备认证:默认可用且放行,可编程拒绝,并记录调用。
class FakeAppLockService implements AppLockService {
  /// isSupported 返回值(模拟"设备没设指纹/PIN")。
  bool supported = true;

  /// 认证结果(false 模拟用户取消/失败)。
  bool result = true;

  /// authenticate / ensureUnlocked 的调用理由记录。
  final List<String> authCalls = [];

  bool _unlocked = false;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> authenticate(String reason) async {
    authCalls.add(reason);
    return result;
  }

  @override
  Future<bool> ensureUnlocked(
    String reason, {
    Duration validFor = const Duration(minutes: 5),
  }) async {
    if (_unlocked) return true;
    authCalls.add(reason);
    if (!result) return false;
    _unlocked = true;
    return true;
  }

  @override
  bool get isUnlocked => _unlocked;

  @override
  void lock() => _unlocked = false;
}

/// 假 VAD 引擎:可编程触发语音段。
class FakeVadEngine extends VadEngine {
  bool _loaded = true;

  @override
  bool get isLoaded => _loaded;

  @override
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
    _loaded = true;
  }

  @override
  Future<void> addSamples(Float32List samples) async {}

  /// 触发一段语音(模拟 VAD 检测到段)。
  void emitSegment(Float32List samples) =>
      onSegment?.call(VadSegment(samples: samples, start: 0));

  @override
  void dispose() {
    _loaded = false;
  }
}

/// 假 PocketTTS 克隆引擎:返回静音音频。
class FakePocketTtsEngine extends PocketTtsEngine {
  @override
  bool get isLoaded => true;

  @override
  Future<void> load({required PocketModelPaths paths, int numThreads = 2}) async {}

  @override
  Future<GeneratedAudioData> generate({
    required String text,
    required Float32List refSamples,
    required int refRate,
    int numSteps = 5,
    int seed = 42,
  }) async =>
      GeneratedAudioData(samples: Float32List(800), sampleRate: 16000);

  @override
  void dispose() {}
}

/// 假 LLM 客户端:逐段产出预设文本块。
class FakeLlmClient implements LlmClient {
  FakeLlmClient({this.chunks = const []});

  final List<String> chunks;
  final List<List<LlmMessage>> capturedMessages = [];

  @override
  Stream<String> streamChat({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<LlmMessage> messages,
    CancelToken? cancel,
  }) async* {
    capturedMessages.add(messages);
    for (final c in chunks) {
      yield c;
    }
  }
}

/// 内存版会话历史存储:与 [SqliteConversationStore] 同接口,供单测用。
class MemoryConversationStore implements ConversationStore {
  final List<ConversationMessage> _all = [];
  int _nextId = 1;

  @override
  Future<void> open() async {}

  @override
  Future<int> insert(ConversationMessage message) async {
    final id = _nextId++;
    _all.add(ConversationMessage(
      id: id,
      role: message.role,
      content: message.content,
      speakerName: message.speakerName,
      createdAt: message.createdAt,
    ));
    return id;
  }

  @override
  Future<List<ConversationMessage>> recent({int limit = 50}) async {
    final sorted = [..._all]..sort((a, b) => a.id!.compareTo(b.id!));
    if (sorted.length <= limit) return sorted;
    return sorted.sublist(sorted.length - limit);
  }

  @override
  Future<List<ConversationMessage>> olderThan({
    required int beforeId,
    int limit = 20,
  }) async {
    final sorted = [..._all]..sort((a, b) => a.id!.compareTo(b.id!));
    final older = sorted.where((m) => m.id! < beforeId).toList();
    if (older.length <= limit) return older;
    return older.sublist(older.length - limit);
  }

  @override
  Future<int> count() async => _all.length;

  @override
  Future<void> deleteById(int id) async {
    _all.removeWhere((m) => m.id == id);
  }

  @override
  Future<void> clearAll() async => _all.clear();

  @override
  Future<void> close() async {}
}
