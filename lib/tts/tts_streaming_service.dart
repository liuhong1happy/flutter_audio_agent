/// 流式 TTS 编排服务(需求 2 + 需求 4)。
///
/// 流程:原文 → 归一化 → 分句/分词 → 后台 isolate 逐句合成 →
/// 顺序播放器排队播放;播放中更新"当前片段"以驱动 UI 高亮与自动滚动。
// ignore_for_file: prefer_initializing_formals
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_dva/flutter_dva.dart';

import '../data/model_catalog.dart';
import '../data/model_manager.dart';
import '../dva/app_dva.dart';
import '../dva/app_models.dart';
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
      _startWordTracking(index);
      _notifyPhase();
    };
    _player.onQueueDrained = () {
      _stopWordTracking();
      if (!_cancelled && _phase != StreamingPhase.error) {
        _phase = StreamingPhase.finished;
        notifyListeners();
      }
    };
  }

  /// 段开始播放时,按"段音频时长 ∝ 词字符权重"逐词推进高亮。
  void _startWordTracking(int segmentIndex) {
    _stopWordTracking();
    _currentWordIndex = 0;
    _wordStopwatch
      ..reset()
      ..start();
    _wordTimer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      final words = _segmentWords.isEmpty ? const <WordSpan>[] : _segmentWords[segmentIndex];
      final duration = _segmentDurations[segmentIndex] ?? 0;
      if (words.isEmpty || duration <= 0) return;
      final realWords = words.where((w) => !w.isSeparator).toList();
      if (realWords.isEmpty) return;
      final totalWeight = realWords.fold<int>(0, (s, w) => s + w.weight);
      final frac =
          (_wordStopwatch.elapsedMilliseconds / 1000.0 / duration).clamp(0.0, 1.0);
      var acc = 0;
      var idx = realWords.length - 1;
      for (var i = 0; i < realWords.length; i++) {
        acc += realWords[i].weight;
        if (frac * totalWeight <= acc) {
          idx = i;
          break;
        }
      }
      final globalIdx = _globalWordIndex(segmentIndex, idx);
      if (globalIdx != _currentWordIndex) {
        _currentWordIndex = globalIdx;
        notifyListeners();
      }
    });
  }

  /// 把"当前片段内的词下标"换算为"整段归一化文本的全局词下标"。
  int _globalWordIndex(int segmentIndex, int segWordIndex) {
    var count = 0;
    for (var s = 0; s < segmentIndex && s < _segmentWords.length; s++) {
      count += _segmentWords[s].where((w) => !w.isSeparator).length;
    }
    return count + segWordIndex;
  }

  /// 分块策略:
  /// - **首句** 按 `1 + 4 + 10 + … + 剩余` 渐进分组:首词尽快出声,
  ///   又不至于像 1+2+4 那样割裂。
  /// - **后续句子** 整句一块(顺滑、自然);超长句(>10 词)按 10 词切分。
  /// - 先按句末标点切句,避免长句/跨句切块。
  List<_ProgressiveChunk> _buildProgressiveChunks(
    List<WordSpan> allWords,
    String text,
  ) {
    const breakChars = '。！？；;.!?…\n';

    // 1. 按标点切句。
    final sentences = <(int, int)>[];
    var sentStart = 0;
    for (var i = 0; i < text.length; i++) {
      if (breakChars.contains(text[i])) {
        sentences.add((sentStart, i + 1));
        sentStart = i + 1;
      }
    }
    if (sentStart < text.length) sentences.add((sentStart, text.length));
    if (sentences.isEmpty) sentences.add((0, text.length));

    // 2. 分块。
    final chunks = <_ProgressiveChunk>[];
    for (var si = 0; si < sentences.length; si++) {
      final (senStart, senEnd) = sentences[si];
      final senWords = allWords
          .where((w) => w.start >= senStart && w.end <= senEnd)
          .toList();
      final real = senWords.where((w) => !w.isSeparator).toList();
      if (real.isEmpty) {
        chunks.add(_ProgressiveChunk(
          segment: TtsSegment(
            text: text.substring(senStart, senEnd),
            start: senStart,
            end: senEnd,
          ),
          words: senWords,
        ));
        continue;
      }

      if (si == 0) {
        // 首句:1 + 4 + 10 + … + 剩余。
        _addPatternChunks(chunks, text, real, senWords, senEnd, const [1, 4, 10]);
      } else if (real.length <= 10) {
        // 后续句:整句一块。
        chunks.add(_ProgressiveChunk(
          segment: TtsSegment(
            text: text.substring(real.first.start, senEnd),
            start: real.first.start,
            end: senEnd,
          ),
          words: senWords,
        ));
      } else {
        // 长句(>10 词):按 10 词切分,末块为剩余。
        _addPatternChunks(chunks, text, real, senWords, senEnd, const [10]);
      }
    }
    return chunks;
  }

  /// 在句内按 [pattern] 尺寸渐进分组(循环使用,末块为剩余)。
  void _addPatternChunks(
    List<_ProgressiveChunk> out,
    String text,
    List<WordSpan> real,
    List<WordSpan> senWords,
    int senEnd,
    List<int> pattern,
  ) {
    var idx = 0;
    var pi = 0;
    while (idx < real.length) {
      final size = pattern[pi < pattern.length ? pi : pattern.length - 1];
      final group = real.skip(idx).take(size).toList();
      final first = group.first;
      final end = idx + size >= real.length ? senEnd : real[idx + size].start;
      out.add(_ProgressiveChunk(
        segment: TtsSegment(
          text: text.substring(first.start, end),
          start: first.start,
          end: end,
        ),
        words: senWords
            .where((w) => w.start >= first.start && w.end <= end)
            .toList(),
      ));
      idx += size;
      pi++;
    }
  }

  void _stopWordTracking() {
    _wordTimer?.cancel();
    _wordTimer = null;
    _wordStopwatch.stop();
    _currentWordIndex = -1;
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

  /// 每段的词级切分(供逐词高亮与全局词索引)。
  List<List<WordSpan>> _segmentWords = [];

  /// 每段音频时长(秒)。
  final Map<int, double> _segmentDurations = {};

  /// 当前正在朗读的词(**整段归一化文本内的全局下标**,-1 = 未开始)。
  int _currentWordIndex = -1;

  Timer? _wordTimer;
  final Stopwatch _wordStopwatch = Stopwatch();

  /// 聊天气泡历史:每次输入一条 Utterance。
  final List<Utterance> _utterances = [];

  /// 当前正在朗读的气泡下标(默认最新)。
  int _activeIndex = -1;

  StreamingPhase get phase => _phase;
  List<TtsSegment> get segments => _segments;
  NormalizationResult? get normalization => _normalization;
  int get currentSegment => _currentSegment;

  /// 当前正在朗读的词(整段内的全局下标)。
  int get currentWordIndex => _currentWordIndex;

  List<List<WordSpan>> get segmentWords => _segmentWords;

  /// 气泡历史(一次输入一条)。
  List<Utterance> get utterances => List.unmodifiable(_utterances);

  /// 正在朗读的那条气泡。
  Utterance? get currentUtterance =>
      (_activeIndex >= 0 && _activeIndex < _utterances.length)
          ? _utterances[_activeIndex]
          : null;

  /// 正在朗读的气泡下标(-1 = 无)。
  int get activeIndex => _activeIndex;

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
    final speakWatch = Stopwatch()..start();
    notifyListeners();

    try {
      // 1. 归一化。
      final norm = _normalizer.normalize(trimmed);
      _normalization = norm;

      // 2. 词级切分 + 渐进分块(1+2+4+…):首词尽快出声,后逐步放宽粒度。
      await _chunker.ensureInitialized();
      final flatWords = _chunker.splitWords(norm.text);
      final chunks = _buildProgressiveChunks(flatWords, norm.text);
      _segments = chunks.map((c) => c.segment).toList();
      _segmentWords = chunks.map((c) => c.words).toList();
      if (_segments.isEmpty) {
        throw StateError('没有可合成的文本');
      }
      final allWords = flatWords;
      _utterances.add(Utterance(
        originalText: trimmed,
        normalizedText: norm.text,
        segments: _segments,
        segmentWords: _segmentWords,
        allWords: allWords,
        normalization: norm,
      ));
      _activeIndex = _utterances.length - 1;
      _utterances.last.stats.tokenizeTime = speakWatch.elapsed;
      _segmentDurations.clear();
      _stopWordTracking();

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

      await _synthesizeSegments(
        session,
        speakWatch: speakWatch,
        utterance: _utterances.last,
      );
      await _persistHistory();
      notifyListeners(); // 刷新气泡耗时统计。
    } catch (e) {
      _lastError = '$e';
      _phase = StreamingPhase.error;
      notifyListeners();
    }
  }

  /// 逐句合成并顺序入队(返回 true = 正常完成,false = 中途出错/被取消)。
  ///
  /// [speakWatch] 从本次朗读开始计时;[utterance] 用于写入耗时统计。
  Future<bool> _synthesizeSegments(
    int session, {
    required Stopwatch speakWatch,
    Utterance? utterance,
  }) async {
    final synthWatch = Stopwatch()..start();
    var firstAudioSet = false;

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
        // 首词音频就绪时间。
        if (!firstAudioSet) {
          firstAudioSet = true;
          utterance?.stats.firstAudioLatency = speakWatch.elapsed;
        }
        _segmentDurations[i] = audio.sampleRate > 0
            ? audio.samples.length / audio.sampleRate
            : 0;
        final wav = wavBytes(audio.samples, audio.sampleRate);
        _segmentWavs[i] = wav; // 缓存供重读。
        _player.enqueue(segmentIndex: i, wavBytes: wav);
      } on Exception catch (e) {
        if (session != _session || _cancelled) break;
        _lastError = '第 ${i + 1} 段合成失败: $e';
        _phase = StreamingPhase.error;
        notifyListeners();
        return false;
      }
    }

    // 汇总耗时统计。
    if (utterance != null) {
      utterance.stats.synthesisTotal = synthWatch.elapsed;
      var totalMs = 0;
      for (final d in _segmentDurations.values) {
        totalMs += (d * 1000).round();
      }
      utterance.stats.audioDuration = Duration(milliseconds: totalMs);
    }
    return true;
  }

  /// 重读某条历史气泡(整段文本,原位播放,不追加新气泡)。
  Future<void> replayUtterance(int index) async {
    if (index < 0 || index >= _utterances.length) return;
    final u = _utterances[index];

    _session++;
    _cancelled = true;
    await _player.stop();
    _stopWordTracking();

    _activeIndex = index;
    _segments = u.segments;
    _segmentWords = u.segmentWords;
    _normalization = u.normalization;
    _rawText = u.originalText;
    _currentSegment = -1;
    _segmentDurations.clear();
    _segmentWavs.clear();

    _phase = StreamingPhase.synthesizing;
    notifyListeners();

    final session = _session;
    _cancelled = false;
    await _synthesizeSegments(
      session,
      speakWatch: Stopwatch()..start(),
      utterance: u,
    );
    await _persistHistory();
    notifyListeners();
  }

  /// 暂停朗读(仅播放中/合成中可暂停)。
  Future<void> pause() async {
    if (_phase != StreamingPhase.playing &&
        _phase != StreamingPhase.synthesizing) {
      return;
    }
    _wordStopwatch.stop();
    _wordTimer?.cancel();
    await _player.pause();
    _phase = StreamingPhase.paused;
    notifyListeners();
  }

  /// 继续朗读。
  Future<void> resume() async {
    if (_phase != StreamingPhase.paused) return;
    _wordStopwatch.start();
    if (_wordTimer == null && _currentSegment >= 0) {
      _startWordTracking(_currentSegment);
    }
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
    _startWordTracking(index);

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
        _segmentDurations[index] = audio.sampleRate > 0
            ? audio.samples.length / audio.sampleRate
            : 0;
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
    _stopWordTracking();
    await _player.stop();
    _phase = StreamingPhase.idle;
    _currentSegment = -1;
    notifyListeners();
  }

  /// 释放播放器与引擎(应用退出时)。
  Future<void> disposeAll() async {
    _session++;
    _cancelled = true;
    _stopWordTracking();
    await _player.dispose();
    _engine.dispose();
  }

  /// 从 flutter_dva 恢复气泡历史(轻量:原文/归一化/毫秒耗时)。
  Future<void> loadHistory() async {
    final store = dvaStore();
    if (store == null) return;
    final h = store.getStateByKey<HistoryState>('history');
    _utterances.clear();
    for (final item in h.items) {
      final original = item['original'] as String? ?? '';
      final u = Utterance(
        originalText: original,
        normalizedText:
            item['normalized'] as String? ?? original,
        segments: const [],
        segmentWords: const [],
        allWords: const [],
      );
      u.stats.fromJson(
        Map<String, dynamic>.from(item['stats'] as Map? ?? const {}),
      );
      _utterances.add(u);
    }
    _activeIndex = -1;
    notifyListeners();
  }

  /// 把气泡历史写入 flutter_dva 持久化(耗时统一毫秒整数)。
  Future<void> _persistHistory() async {
    final store = dvaStore();
    if (store == null) return;
    await store.dispatch(
      DvaAction('history/setItems', _utterances.map((u) {
        return <String, dynamic>{
          'original': u.originalText,
          'normalized': u.normalizedText,
          'stats': u.stats.toJson(),
        };
      }).toList()),
    );
  }
}

/// 一个渐进分块:待合成文本段 + 段内词(含分隔符)。
class _ProgressiveChunk {
  const _ProgressiveChunk({required this.segment, required this.words});

  final TtsSegment segment;
  final List<WordSpan> words;
}
