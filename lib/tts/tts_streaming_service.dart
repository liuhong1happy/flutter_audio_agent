/// 流式 TTS 编排服务(需求 2 + 需求 4)。
///
/// 流程:原文 → 归一化 → 分句/分词 → 后台 isolate 逐句合成 →
/// 顺序播放器排队播放;播放中更新"当前片段"以驱动 UI 高亮与自动滚动。
// ignore_for_file: prefer_initializing_formals
library;

import 'package:flutter/foundation.dart';

import '../data/model_catalog.dart';
import '../data/model_manager.dart';
import '../models/tts_settings.dart';
import 'sequential_audio_player.dart';
import 'text_chunker.dart';

import 'text_normalizer.dart';
import 'tts_engine.dart';
import 'wav_encoder.dart';

/// 流式合成阶段。
enum StreamingPhase {
  idle,
  preparing,
  synthesizing,
  playing,
  paused,
  finished,
  error,
}

class TtsStreamingService extends ChangeNotifier {
  TtsStreamingService({
    required TextNormalizer normalizer,
    required TextChunker chunker,
    required TtsEngine engine,
    required ModelManager modelManager,
    required TtsSettings settings,
    AudioPlaybackQueue? player,
  })  : _normalizer = normalizer,
        _chunker = chunker,
        _engine = engine,
        _modelManager = modelManager,
        _settings = settings,
        _player = player ?? SequentialAudioPlayer() {
    _player.onSegmentStarted = (index) {
      _currentSegment = index;
      _notifyPhase();
    };
    _player.onQueueDrained = () {
      if (!_cancelled && _phase != StreamingPhase.error) {
        _phase = StreamingPhase.finished;
        notifyListeners();
      }
    };
  }

  final TextNormalizer _normalizer;
  final TextChunker _chunker;
  final TtsEngine _engine;
  final ModelManager _modelManager;
  final TtsSettings _settings;
  final AudioPlaybackQueue _player;

  StreamingPhase _phase = StreamingPhase.idle;
  List<TtsSegment> _segments = const [];
  NormalizationResult? _normalization;
  int _currentSegment = -1;
  String? _lastError;
  String _rawText = '';
  String? _loadedModelId;
  bool _cancelled = false;

  /// 会话令牌:每次 speak/stop 递增,用于丢弃过期合成的音频。
  int _session = 0;

  /// 每段已合成 WAV 的缓存(按片段下标),供"气泡重读"复用。
  final Map<int, Uint8List> _segmentWavs = {};

  StreamingPhase get phase => _phase;
  List<TtsSegment> get segments => _segments;
  NormalizationResult? get normalization => _normalization;
  int get currentSegment => _currentSegment;
  String? get lastError => _lastError;
  String get rawText => _rawText;

  double get progress {
    if (_segments.isEmpty) return 0;
    final played = _currentSegment + 1;
    return (played / _segments.length).clamp(0.0, 1.0);
  }

  void _notifyPhase() {
    if (_phase == StreamingPhase.synthesizing) {
      _phase = StreamingPhase.playing;
    }
    notifyListeners();
  }

  /// 开始朗读 [rawText]。
  Future<void> speak(String rawText) async {
    await stop();

    final trimmed = rawText.trim();
    if (trimmed.isEmpty) {
      _lastError = '请输入文本';
      _phase = StreamingPhase.error;
      notifyListeners();
      return;
    }

    _rawText = trimmed;
    _phase = StreamingPhase.preparing;
    _cancelled = false;
    final session = ++_session;
    notifyListeners();

    try {
      // 1. 归一化。
      final norm = _normalizer.normalize(trimmed);
      _normalization = norm;

      // 2. 分句/分词。
      await _chunker.ensureInitialized();
      _segments = _chunker.chunk(norm.text);
      if (_segments.isEmpty) {
        throw StateError('没有可合成的文本');
      }

      // 3. 确保引擎加载了所选模型。
      final model = ModelCatalog.byId(_settings.selectedModelId);
      if (model == null) {
        throw StateError('请先在"设置"中选择一个模型');
      }
      if (!_modelManager.isDownloaded(model.id)) {
        throw StateError('所选模型尚未下载,请到"模型管理"下载');
      }
      final paths = _modelManager.resolveModel(model);
      if (paths == null) {
        throw StateError('模型文件缺失,请重新下载');
      }
      if (!_engine.isLoaded || _loadedModelId != model.id) {
        _phase = StreamingPhase.preparing;
        notifyListeners();
        await _engine.load(paths: paths, model: model, settings: _settings);
        _loadedModelId = model.id;
      }

      // 4. 逐句合成入队(后台 isolate,主 isolate 播放不受阻)。
      _phase = StreamingPhase.synthesizing;
      _segmentWavs.clear();
      notifyListeners();

      for (var i = 0; i < _segments.length; i++) {
        if (session != _session || _cancelled) break;
        final seg = _segments[i];
        try {
          final audio = await _engine.generate(
            text: seg.text,
            sid: _settings.sid,
            speed: _settings.speed,
          );
          if (session != _session || _cancelled) break;
          final wav = wavBytes(audio.samples, audio.sampleRate);
          _segmentWavs[i] = wav; // 缓存供重读。
          _player.enqueue(segmentIndex: i, wavBytes: wav);
        } on Exception catch (e) {
          if (session != _session || _cancelled) break;
          _lastError = '第 ${i + 1} 段合成失败: $e';
          _phase = StreamingPhase.error;
          notifyListeners();
          return;
        }
      }
    } catch (e) {
      _lastError = '$e';
      _phase = StreamingPhase.error;
      notifyListeners();
    }
  }

  /// 暂停朗读(仅播放中/合成中可暂停)。
  Future<void> pause() async {
    if (_phase != StreamingPhase.playing &&
        _phase != StreamingPhase.synthesizing) {
      return;
    }
    await _player.pause();
    _phase = StreamingPhase.paused;
    notifyListeners();
  }

  /// 继续朗读。
  Future<void> resume() async {
    if (_phase != StreamingPhase.paused) return;
    await _player.resume();
    _phase = StreamingPhase.playing;
    notifyListeners();
  }

  /// 重读某一段(气泡点击)。复用已缓存音频,未缓存则现合成。
  ///
  /// 会停止当前整段流水线,只播放指定片段;气泡列表保留。
  Future<void> replaySegment(int index) async {
    if (index < 0 || index >= _segments.length) return;

    _session++;
    _cancelled = true;
    await _player.stop();
    _currentSegment = index;

    var wav = _segmentWavs[index];
    if (wav == null) {
      try {
        final seg = _segments[index];
        final audio = await _engine.generate(
          text: seg.text,
          sid: _settings.sid,
          speed: _settings.speed,
        );
        wav = wavBytes(audio.samples, audio.sampleRate);
        _segmentWavs[index] = wav;
      } on Exception {
        _lastError = '第 ${index + 1} 段合成失败';
        _phase = StreamingPhase.error;
        notifyListeners();
        return;
      }
    }

    _phase = StreamingPhase.playing;
    notifyListeners();
    _player.enqueue(segmentIndex: index, wavBytes: wav);
  }

  /// 停止播放;保留已分句的气泡列表(可继续重读),下次 speak 时替换。
  Future<void> stop() async {
    _session++;
    _cancelled = true;
    await _player.stop();
    _phase = StreamingPhase.idle;
    _currentSegment = -1;
    notifyListeners();
  }

  /// 释放播放器与引擎(应用退出时)。
  Future<void> disposeAll() async {
    await _player.dispose();
    _engine.dispose();
  }
}
