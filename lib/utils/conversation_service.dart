/// 语音对话编排服务(说话人感知,VAD 常开)。
///
/// 状态机:
/// `idle → listening → asr → identifying → thinking → speaking → listening`,
/// 任意态可 stop 回 idle;mute 关麦克风输入。
///
/// 会话历史为**单一时间线**(不分说话人桶),存 SQLite,按时间排序、分页。
/// 每轮:VAD 段 → ASR 转写 → 声纹识别说话人 → 追加用户消息 → 构建 LLM
/// 提示(注入当前说话人身份/备注 + 近期历史)→ 流式累积 → 分块合成播放 →
/// 恢复聆听。未知说话人走访客模式。
// ignore_for_file: prefer_initializing_formals
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter_tts_demo/utils/asr_service.dart';
import 'package:flutter_tts_demo/utils/mic_recorder.dart';
import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/data/model_manager.dart';
import 'package:flutter_tts_demo/utils/llm_client.dart';
import 'package:flutter_tts_demo/utils/llm_service.dart';
import 'package:flutter_tts_demo/data/models/tts_model.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/utils/sequential_audio_player.dart';
import 'package:flutter_tts_demo/utils/text_chunker.dart';
import 'package:flutter_tts_demo/utils/engines/tts_engine.dart';
import 'package:flutter_tts_demo/utils/tts_streaming_service.dart';
import 'package:flutter_tts_demo/utils/engines/vad_engine.dart';
import 'package:flutter_tts_demo/utils/wav_encoder.dart';
import 'package:flutter_tts_demo/utils/voice_cloning_service.dart';
import 'package:flutter_tts_demo/utils/voiceprint_service.dart';
import 'package:flutter_tts_demo/data/models/conversation_message.dart';
import 'package:flutter_tts_demo/data/conversation_store.dart';

/// 对话阶段。
enum ConversationPhase { idle, listening, asr, identifying, thinking, speaking, error }

/// 对话发音路由。
sealed class ConversationVoice {
  const ConversationVoice();
}

class ModelVoice extends ConversationVoice {
  const ModelVoice({required this.modelId, this.sid = 0});
  final String modelId;
  final int sid;
}

class CloneVoice extends ConversationVoice {
  const CloneVoice({required this.cloneId});
  final String cloneId;
}

class ConversationService extends ChangeNotifier {
  ConversationService({
    required ModelManager modelManager,
    required TtsSettings settings,
    required AsrService asr,
    required VoiceprintService voiceprint,
    required VoiceCloningService cloning,
    required LlmService llm,
    required TextChunker chunker,
    required TtsEngine ttsEngine,
    required TtsStreamingService streamingService,
    required MicRecorder mic,
    required ConversationStore store,
    VadEngine? vad,
    AudioPlaybackQueue? player,
  })  : _modelManager = modelManager,
        _settings = settings,
        _asr = asr,
        _voiceprint = voiceprint,
        _cloning = cloning,
        _llm = llm,
        _chunker = chunker,
        _ttsEngine = ttsEngine,
        _streamingService = streamingService,
        _mic = mic,
        _store = store,
        _vad = vad ?? VadEngine() {
    _vad.onSegment = _onVadSegment;
    _player = player ?? SequentialAudioPlayer();
    _player.onQueueDrained = _onPlaybackDrained;
  }

  final ModelManager _modelManager;
  final TtsSettings _settings;
  final AsrService _asr;
  final VoiceprintService _voiceprint;
  final VoiceCloningService _cloning;
  final LlmService _llm;
  final TextChunker _chunker;
  final TtsEngine _ttsEngine;
  final TtsStreamingService _streamingService;
  final MicRecorder _mic;
  final ConversationStore _store;
  final VadEngine _vad;
  late final AudioPlaybackQueue _player;

  static const String _defaultSystemPrompt =
      '你是一个友好的中文语音助手。请用简洁自然、适合朗读的中文口语回答,不要使用列表或表情符号。';

  /// 单页加载的近期消息数。
  static const int _recentLimit = 50;

  /// 向前翻页的页大小。
  static const int _pageSize = 20;

  /// 喂给 LLM 的近期历史条数。
  static const int _llmContextLimit = 20;

  ConversationPhase _phase = ConversationPhase.idle;
  String? _currentSpeaker;
  final List<ConversationMessage> _messages = [];
  bool _hasMore = false;
  int? _oldestId;
  String _streamingText = '';
  bool _micActive = false;
  bool _muted = false;
  String? _lastError;

  StreamSubscription<Uint8List>? _micSub;
  CancelToken? _cancelToken;
  int _session = 0;
  bool _historyLoaded = false;
  String? _loadedModelVoiceId;
  List<TtsSegment> _segments = const [];
  int _currentSegmentIndex = -1;

  // ── 只读状态 ──────────────────────────────────────────────────────

  ConversationPhase get phase => _phase;

  /// 当前说话人名字(null = 未知/访客)。
  String? get currentSpeaker => _currentSpeaker;

  /// 已加载的会话消息(单一时间线,旧→新)。
  List<ConversationMessage> get messages => List.unmodifiable(_messages);

  /// 是否还有更早的历史可翻页。
  bool get hasMore => _hasMore;

  String get streamingText => _streamingText;
  bool get isMicActive => _micActive;
  bool get isMuted => _muted;
  String? get lastError => _lastError;

  /// 正在朗读的片段下标(-1 = 无)。
  int get currentSegment => _currentSegmentIndex;

  /// 是否已具备开始对话的条件(三件套就绪 + 至少一个发音可用)。
  bool get isReadyForConversation {
    final vad = ModelCatalog.byKind(ModelKind.vad);
    if (vad == null || !_modelManager.isDownloaded(vad.id)) return false;
    final asrId = _settings.asrModelId;
    if (asrId == null) return false;
    final asr = ModelCatalog.byId(asrId);
    if (asr == null || !_modelManager.isDownloaded(asr.id)) return false;
    return _hasUsableVoice();
  }

  bool _hasUsableVoice() {
    if (_settings.conversationVoiceType == ConversationVoiceType.clone) {
      return _settings.conversationCloneId != null &&
          _cloning.byId(_settings.conversationCloneId) != null;
    }
    final modelId = _settings.conversationModelVoiceId;
    if (modelId == null) return false;
    final m = ModelCatalog.byId(modelId);
    return m != null && _modelManager.isDownloaded(m.id);
  }

  /// 一键初始化:下载三件套缺省模型并自动配置 ASR + 对话发音。
  Future<void> downloadInitialModels(
    void Function(double progress)? onProgress,
  ) async {
    final ids = kDefaultConversationModelIds;
    final targets = [ids['vad'], ids['asr'], ids['tts']]
        .map(ModelCatalog.byId)
        .whereType<TtsModel>()
        .where((m) => !_modelManager.isDownloaded(m.id))
        .toList();
    for (var i = 0; i < targets.length; i++) {
      await _modelManager.downloadModel(targets[i]);
      onProgress?.call((i + 1) / targets.length);
    }
    if (_settings.asrModelId == null) {
      await _settings.setAsrModelId(ids['asr']);
    }
    if (_settings.conversationModelVoiceId == null) {
      final selected = ModelCatalog.byId(_settings.selectedModelId);
      final voiceId = (selected != null && selected.kind == ModelKind.tts)
          ? selected.id
          : ids['tts']!;
      await _settings.setConversationVoiceModel(voiceId, 0);
    }
    notifyListeners();
  }

  /// 从 SQLite 加载近期历史(启动时调用,幂等)。
  Future<void> loadHistory() async {
    if (_historyLoaded) return;
    _historyLoaded = true;
    await _store.open();
    final recent = await _store.recent(limit: _recentLimit);
    _messages
      ..clear()
      ..addAll(recent);
    _hasMore = recent.length == _recentLimit;
    _oldestId = recent.isEmpty ? null : recent.first.id;
    notifyListeners();
  }

  /// 向前翻页:加载更早的历史,前置到 [_messages]。
  Future<void> loadOlder() async {
    if (!_hasMore || _oldestId == null) return;
    final older = await _store.olderThan(beforeId: _oldestId!, limit: _pageSize);
    if (older.isEmpty) {
      _hasMore = false;
      notifyListeners();
      return;
    }
    _messages.insertAll(0, older);
    _hasMore = older.length == _pageSize;
    _oldestId = older.first.id;
    notifyListeners();
  }

  // ── 生命周期 ──────────────────────────────────────────────────────

  Future<void> start() async {
    try {
      final ok = await _mic.hasPermission();
      if (!ok) {
        _lastError = 'micPermissionDenied';
        _phase = ConversationPhase.error;
        notifyListeners();
        return;
      }
      await _ensureVadLoaded();
      await _asr.ensureLoaded();
      if (!_vad.isLoaded) {
        _lastError = 'vadNotReady';
        _phase = ConversationPhase.error;
        notifyListeners();
        return;
      }
      _micActive = true;
      _lastError = null;
      _phase = ConversationPhase.listening;
      notifyListeners();
      await _startMicStream();
    } catch (e) {
      _lastError = '$e';
      _phase = ConversationPhase.error;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _session++;
    _cancelToken?.cancel();
    _cancelToken = null;
    _micActive = false;
    await _stopMicStream();
    await _player.stop();
    _streamingText = '';
    _phase = ConversationPhase.idle;
    notifyListeners();
  }

  Future<void> toggleMute() async {
    _muted = !_muted;
    if (_muted) {
      await _stopMicStream();
    } else if (_micActive && _phase == ConversationPhase.listening) {
      await _startMicStream();
    }
    notifyListeners();
  }

  Future<void> clearHistory() async {
    await _store.clearAll();
    _messages.clear();
    _hasMore = false;
    _oldestId = null;
    _currentSpeaker = null;
    notifyListeners();
  }

  /// 删除单条消息(内存 + 落库)。
  Future<void> deleteMessage(int id) async {
    _messages.removeWhere((m) => m.id == id);
    await _store.deleteById(id);
    notifyListeners();
  }

  /// 文本模式:手动输入 → LLM → 纯文本回复(不转 TTS、不走麦克风)。
  Future<void> sendText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    // 中止任何进行中的语音回复。
    _session++;
    _cancelToken?.cancel();
    _cancelToken = null;
    await _player.stop();
    _currentSpeaker = null;
    _phase = ConversationPhase.thinking;
    _streamingText = '';
    notifyListeners();

    try {
      // 追加用户消息(落库 + 内存)。
      final userMsg = await _persist(ConversationMessage(
        role: ConversationRole.user,
        content: trimmed,
        speakerName: null,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      _messages.add(userMsg);

      // LLM 流式(纯文本)。
      final messages = _buildLlmMessages();
      final cancel = CancelToken();
      _cancelToken = cancel;
      final buffer = StringBuffer();
      try {
        await for (final delta in _llm.streamChat(messages, cancel: cancel)) {
          buffer.write(delta);
          _streamingText = buffer.toString();
          notifyListeners();
        }
      } on StateError catch (e) {
        _lastError = e.message;
        _phase = ConversationPhase.error;
        notifyListeners();
        return;
      } finally {
        _cancelToken = null;
      }

      final reply = buffer.toString().trim();
      _streamingText = '';
      if (reply.isEmpty) {
        _phase = ConversationPhase.idle;
        notifyListeners();
        return;
      }

      // 追加助手消息(纯文本,无音频)。
      final assistantMsg = await _persist(ConversationMessage(
        role: ConversationRole.assistant,
        content: reply,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      _messages.add(assistantMsg);
      _phase = ConversationPhase.idle;
      notifyListeners();
    } catch (e) {
      _lastError = '$e';
      _phase = ConversationPhase.error;
      notifyListeners();
    }
  }

  /// 落库并返回带自增 id 的消息。
  Future<ConversationMessage> _persist(ConversationMessage m) async {
    final id = await _store.insert(m);
    return ConversationMessage(
      id: id,
      role: m.role,
      content: m.content,
      speakerName: m.speakerName,
      createdAt: m.createdAt,
    );
  }

  // ── 内部:麦克风 / VAD ─────────────────────────────────────────────

  Future<void> _ensureVadLoaded() async {
    if (_vad.isLoaded) return;
    final model = ModelCatalog.byKind(ModelKind.vad);
    if (model == null) return;
    if (!_modelManager.isDownloaded(model.id)) return;
    final paths = _modelManager.resolveModel(model);
    if (paths == null || paths.modelPath == null) return;
    await _vad.load(
      model: paths.modelPath!,
      threshold: _settings.vadThreshold,
      minSilenceDuration: _settings.vadMinSilence,
      maxSpeechDuration: _settings.vadMaxSpeech,
    );
  }

  Future<void> _startMicStream() async {
    if (_micSub != null) return;
    final stream = await _mic.startStream(sampleRate: 16000);
    _micSub = stream.listen((chunk) {
      _vad.addSamples(pcm16ToFloat32(chunk));
    });
  }

  Future<void> _stopMicStream() async {
    await _micSub?.cancel();
    _micSub = null;
    await _mic.stopStream();
  }

  Future<void> _resumeMic() async {
    if (_micActive && !_muted) {
      await _startMicStream();
    }
  }

  void _onVadSegment(VadSegment segment) {
    if (_phase != ConversationPhase.listening) return;
    unawaited(_handleSegment(segment.samples));
  }

  // ── 每轮处理 ──────────────────────────────────────────────────────

  Future<void> _handleSegment(Float32List samples) async {
    if (_muted) return;
    _phase = ConversationPhase.asr;
    notifyListeners();
    try {
      // 1. ASR 转写。
      final result = await _asr.recognize(samples, 16000);
      final text = result.text.trim();
      if (text.isEmpty) {
        _phase = ConversationPhase.listening;
        notifyListeners();
        return;
      }

      // 2. 声纹识别说话人。
      _phase = ConversationPhase.identifying;
      notifyListeners();
      final name = await _voiceprint.identify(samples, 16000);
      _currentSpeaker = name.isEmpty ? null : name;
      notifyListeners();

      // 3. 追加用户消息(落库 + 内存)。
      final userMsg = await _persist(ConversationMessage(
        role: ConversationRole.user,
        content: text,
        speakerName: _currentSpeaker,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      _messages.add(userMsg);

      // 4. 停止麦克风,防自听反馈。
      await _stopMicStream();

      // 5. LLM 流式。
      _phase = ConversationPhase.thinking;
      _streamingText = '';
      notifyListeners();

      final messages = _buildLlmMessages();
      final cancel = CancelToken();
      _cancelToken = cancel;
      final buffer = StringBuffer();
      try {
        await for (final delta in _llm.streamChat(messages, cancel: cancel)) {
          buffer.write(delta);
          _streamingText = buffer.toString();
          notifyListeners();
        }
      } on StateError catch (e) {
        _lastError = e.message;
        _phase = ConversationPhase.error;
        notifyListeners();
        _resumeMic();
        return;
      } finally {
        _cancelToken = null;
      }

      final reply = buffer.toString().trim();
      _streamingText = '';
      if (reply.isEmpty) {
        _phase = ConversationPhase.listening;
        notifyListeners();
        _resumeMic();
        return;
      }

      // 6. 追加助手消息(落库 + 内存)。
      final assistantMsg = await _persist(ConversationMessage(
        role: ConversationRole.assistant,
        content: reply,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      _messages.add(assistantMsg);
      notifyListeners();

      // 7. 合成播放回复。
      await _speakReply(reply);
    } catch (e) {
      _lastError = '$e';
      _phase = ConversationPhase.error;
      notifyListeners();
      await _resumeMic();
    }
  }

  List<LlmMessage> _buildLlmMessages() {
    final out = <LlmMessage>[];
    final base = _settings.llmSystemPrompt.trim().isEmpty
        ? _defaultSystemPrompt
        : _settings.llmSystemPrompt.trim();
    final profile =
        _currentSpeaker == null ? null : _voiceprint.profileOf(_currentSpeaker!);

    final sys = StringBuffer(base);
    if (_currentSpeaker == null) {
      sys.write('\n当前说话人: 未知用户');
    } else {
      sys.write('\n当前说话人: $_currentSpeaker');
      if (profile != null && profile.note.trim().isNotEmpty) {
        sys.write('\n说话人备注: ${profile.note.trim()}');
      }
    }
    out.add(LlmMessage(role: 'system', content: sys.toString()));

    // 近期历史(单一时间线),用户消息带说话人前缀。
    final recent = _messages.length <= _llmContextLimit
        ? _messages
        : _messages.sublist(_messages.length - _llmContextLimit);
    for (final m in recent) {
      if (m.role == ConversationRole.user) {
        final who = m.speakerName ?? '未知';
        out.add(LlmMessage(role: 'user', content: '[$who] ${m.content}'));
      } else {
        out.add(LlmMessage(role: 'assistant', content: m.content));
      }
    }
    return out;
  }

  // ── 合成播放 ──────────────────────────────────────────────────────

  Future<void> _speakReply(String text) async {
    await _chunker.ensureInitialized();
    final segments = _chunker.chunk(text);
    if (segments.isEmpty) {
      _phase = ConversationPhase.listening;
      notifyListeners();
      await _resumeMic();
      return;
    }
    _segments = segments;
    _currentSegmentIndex = -1;
    _phase = ConversationPhase.speaking;
    notifyListeners();

    // 防与合成页重叠。
    await _streamingService.stop();

    final session = ++_session;
    _player.nextSegmentProvider = (index) async {
      if (session != _session) return null;
      if (index < 0 || index >= _segments.length) return null;
      try {
        final audio = await _synthesizeChunk(_segments[index].text);
        if (session != _session) return null;
        return wavBytes(audio.samples, audio.sampleRate);
      } catch (e) {
        if (session != _session) return null;
        _lastError = '$e';
        _phase = ConversationPhase.error;
        notifyListeners();
        return null;
      }
    };
    _player.onSegmentStarted = (i) {
      _currentSegmentIndex = i;
      notifyListeners();
    };
    unawaited(_player.play());
  }

  Future<GeneratedAudioData> _synthesizeChunk(String text) async {
    final voice = _currentVoice();
    if (voice is ModelVoice) {
      await _ensureModelVoiceLoaded(voice);
      return _ttsEngine.generate(text: text, sid: voice.sid, speed: 1.0);
    }
    if (voice is CloneVoice) {
      final profile = _cloning.byId(voice.cloneId);
      if (profile == null) throw StateError('克隆音已删除');
      return _cloning.synthesize(text, profile);
    }
    throw StateError('未选择对话发音');
  }

  ConversationVoice _currentVoice() {
    if (_settings.conversationVoiceType == ConversationVoiceType.clone &&
        _settings.conversationCloneId != null) {
      return CloneVoice(cloneId: _settings.conversationCloneId!);
    }
    return ModelVoice(
      modelId: _settings.conversationModelVoiceId ?? '',
      sid: _settings.conversationSid,
    );
  }

  Future<void> _ensureModelVoiceLoaded(ModelVoice voice) async {
    if (voice.modelId.isEmpty) throw StateError('未选择模型声音');
    final model = ModelCatalog.byId(voice.modelId);
    if (model == null) throw StateError('模型不存在');
    if (!_modelManager.isDownloaded(model.id)) throw StateError('模型未下载');
    final paths = _modelManager.resolveModel(model);
    if (paths == null) throw StateError('模型文件缺失');
    if (_ttsEngine.isLoaded && _loadedModelVoiceId == voice.modelId) return;
    await _ttsEngine.load(paths: paths, model: model, settings: _settings);
    _loadedModelVoiceId = voice.modelId;
  }

  void _onPlaybackDrained() {
    if (_phase != ConversationPhase.speaking) return;
    _currentSegmentIndex = -1;
    _phase = ConversationPhase.listening;
    notifyListeners();
    unawaited(_resumeMic());
  }

  @override
  void dispose() {
    _session++;
    _cancelToken?.cancel();
    _micSub?.cancel();
    _vad.dispose();
    _player.dispose();
    super.dispose();
  }
}
