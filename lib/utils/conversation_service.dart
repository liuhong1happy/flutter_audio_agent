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
import 'package:flutter_tts_demo/data/models/memory_item.dart';
import 'package:flutter_tts_demo/utils/memory/context_assembler.dart';
import 'package:flutter_tts_demo/utils/memory/knowledge_service.dart';
import 'package:flutter_tts_demo/utils/memory/memory_service.dart';
import 'package:flutter_tts_demo/utils/memory/session_memory_service.dart';
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
    KnowledgeService? knowledge,
    MemoryService? memory,
    SessionMemoryService? sessionMemory,
    ContextAssembler? assembler,
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
        _vad = vad ?? VadEngine(),
        _knowledge = knowledge,
        _memory = memory,
        _sessionMemory = sessionMemory,
        _assembler = assembler ?? ContextAssembler() {
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

  /// 知识库检索(可空:未接入时退化为 v1.0.1 行为,不注入任何片段)。
  final KnowledgeService? _knowledge;

  /// 长期记忆(可空)。
  final MemoryService? _memory;

  /// 短期记忆/会话分段(可空)。
  final SessionMemoryService? _sessionMemory;

  /// 上下文编排器(预算与裁剪策略都封在里面)。
  final ContextAssembler _assembler;

  late final AudioPlaybackQueue _player;

  /// 最近一次编排的诊断(供 UI 显示"引用了 N 条资料"/排查未注入原因)。
  AssembledContext? _lastContext;
  AssembledContext? get lastContext => _lastContext;

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

  /// 文本模式就绪:只需配好大模型。
  ///
  /// [sendText] 只碰 LLM 与 SQLite —— 不用 VAD/ASR/TTS/声纹/麦克风,所以文本
  /// 模式**一个本地模型都不需要下载**。
  bool get isReadyForTextMode => _settings.isLlmConfigured;

  /// 音频模式就绪:三件套(见 [isReadyForConversation])+ 大模型。
  ///
  /// 注意:门禁只在 UI 层,没有加进 [start()] —— `start()` 保持"模型不齐才
  /// 拒绝、未配 Key 则起得来、命中 LLM 时才报错"的既有行为,那条运行时错误
  /// 路径有测试覆盖。
  bool get isReadyForAudioMode =>
      isReadyForConversation && _settings.isLlmConfigured;

  /// 是否已具备开始对话的条件(三件套就绪 + 至少一个发音可用)。
  ///
  /// **不含大模型条件** —— 那是模式相关的,见 [isReadyForTextMode] /
  /// [isReadyForAudioMode]。
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
      // 门禁 fail-closed:开了门禁却一个声纹都没注册,白名单就是空的,放行
      // 等于没门禁。宁可拒绝启动并说明原因,也不给用户虚假的安全感。
      // 判据是"任何模型下"——identify 是跨模型并集,只看当前模型会误判。
      if (_settings.voiceprintGateEnabled && !_voiceprint.hasAnyProfiles) {
        _lastError = 'voiceprintGateNoProfiles';
        _phase = ConversationPhase.error;
        notifyListeners();
        return;
      }
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
      final messages = await _buildLlmMessages();
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
      _afterTurn();
    } catch (e) {
      _lastError = '$e';
      _phase = ConversationPhase.error;
      notifyListeners();
    }
  }

  /// 落库并返回带自增 id 的消息。
  ///
  /// **会话分段在这里统一补上**,而不是让每个调用点各自传 ——
  /// 音频模式与文本模式各有多个落库点,漏一处就会出现"这条消息不属于任何会话",
  /// 那样它永远不会被摘要(而用户完全看不出来)。
  Future<ConversationMessage> _persist(ConversationMessage m) async {
    final sessionId =
        m.sessionId ?? _sessionMemory?.sessionIdAt(m.createdAt);
    final withSession = ConversationMessage(
      id: m.id,
      role: m.role,
      content: m.content,
      speakerName: m.speakerName,
      createdAt: m.createdAt,
      sessionId: sessionId,
    );
    final id = await _store.insert(withSession);
    return ConversationMessage(
      id: id,
      role: m.role,
      content: m.content,
      speakerName: m.speakerName,
      createdAt: m.createdAt,
      sessionId: sessionId,
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

    // 1. 声纹识别说话人。
    //    刻意放在 ASR **之前**:门禁拒绝时可以直接返回,省掉 ASR + LLM
    //    两次推理 —— 拒绝比放行便宜。identify 只需要音频段,不需要文本。
    _phase = ConversationPhase.identifying;
    notifyListeners();
    final name = await _voiceprint.identify(samples, 16000);
    _currentSpeaker = name.isEmpty ? null : name;
    notifyListeners();

    // 2. 声纹门禁:不在白名单的人不转写、不落库、不问 LLM。
    if (_settings.voiceprintGateEnabled && _currentSpeaker == null) {
      await _rejectByGate();
      return;
    }

    _phase = ConversationPhase.asr;
    notifyListeners();
    try {
      // 3. ASR 转写。
      final result = await _asr.recognize(samples, 16000);
      final text = result.text.trim();
      if (text.isEmpty) {
        _phase = ConversationPhase.listening;
        notifyListeners();
        return;
      }

      // 4. 追加用户消息(落库 + 内存)。
      final userMsg = await _persist(ConversationMessage(
        role: ConversationRole.user,
        content: text,
        speakerName: _currentSpeaker,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      _messages.add(userMsg);

      // 5. 停止麦克风,防自听反馈。
      await _stopMicStream();

      // 6. LLM 流式。
      _phase = ConversationPhase.thinking;
      _streamingText = '';
      notifyListeners();

      final messages = await _buildLlmMessages();
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
      _afterTurn();

      // 7. 合成播放回复。
      await _speakReply(reply);
    } catch (e) {
      _lastError = '$e';
      _phase = ConversationPhase.error;
      notifyListeners();
      await _resumeMic();
    }
  }

  /// 最近一条**用户**消息的文本(检索查询用它)。
  String _lastUserText() {
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].role == ConversationRole.user) {
        return _messages[i].content;
      }
    }
    return '';
  }

  /// 每轮结束后的收尾:**一律不阻塞主流程**,且全部失败静默。
  ///
  /// 这里放的是"增强"类工作(滚动摘要、记忆抽取)。它们失败只该少一点记忆,
  /// 绝不该让用户说不下去话 —— 故都是 fire-and-forget。
  void _afterTurn() {
    final sm = _sessionMemory;
    final sid = sm?.currentSessionId;
    if (sm != null && sid != null) {
      unawaited(sm.maybeSummarize(sessionId: sid));
    }

    final mem = _memory;
    // 开关关闭就不抽取 —— 抽取会消耗用户自付的 API token。
    if (mem != null && _settings.memoryEnabled) {
      mem.noteTurn();
      if (mem.shouldExtract) {
        // 只喂最近若干轮:更早的内容已经进摘要了,重复喂既费 token 也易抽重。
        final from = _messages.length > _extractWindow
            ? _messages.length - _extractWindow
            : 0;
        unawaited(mem.extractFrom(
          speaker: _currentSpeaker,
          recentMessages: _messages.sublist(from),
        ));
      }
    }
  }

  /// 记忆抽取时喂给 LLM 的最近消息条数。
  static const int _extractWindow = 10;

  /// 构建发给 LLM 的消息。
  ///
  /// 由 [ContextAssembler] 统一做预算与裁剪:知识库片段、长期记忆、会话摘要、
  /// 最近若干轮都在这里汇合。**任何检索失败都只是"不注入"**,绝不影响对话。
  Future<List<LlmMessage>> _buildLlmMessages() async {
    final base = _settings.llmSystemPrompt.trim().isEmpty
        ? _defaultSystemPrompt
        : _settings.llmSystemPrompt.trim();
    final profile =
        _currentSpeaker == null ? null : _voiceprint.profileOf(_currentSpeaker!);

    // 近期历史(单一时间线),用户消息带说话人前缀。
    final recent = _messages.length <= _llmContextLimit
        ? _messages
        : _messages.sublist(_messages.length - _llmContextLimit);
    final recentMessages = <LlmMessage>[
      for (final m in recent)
        if (m.role == ConversationRole.user)
          LlmMessage(role: 'user', content: '[${m.speakerName ?? '未知'}] ${m.content}')
        else
          LlmMessage(role: 'assistant', content: m.content),
    ];

    final query = _lastUserText();

    // ③ 知识库(开关关闭 / 空查询 / 检索失败 ⇒ 空列表)
    var knowledge = const <ContextSnippet>[];
    final kb = _knowledge;
    if (_settings.kbEnabled && kb != null && query.trim().isNotEmpty) {
      final hits = await kb.search(query);
      if (hits.isNotEmpty) {
        final titles = {for (final d in kb.documents) d.id: d.title};
        knowledge = [
          for (final h in hits)
            if ((h.text ?? '').trim().isNotEmpty)
              ContextSnippet(
                text: h.text!,
                label: h.payload is int ? titles[h.payload as int] : null,
              ),
        ];
      }
    }

    // ④ 长期记忆(未知说话人 ⇒ MemoryService 内部直接返回空,这里无需再判)
    var memories = const <MemoryItem>[];
    final mem = _memory;
    if (mem != null && query.trim().isNotEmpty) {
      memories = await mem.retrieve(
        speaker: _currentSpeaker,
        query: query,
        topK: _settings.memoryTopK,
      );
    }

    // ⑤ 会话摘要
    String? summary;
    final sm = _sessionMemory;
    final sid = sm?.currentSessionId;
    if (sm != null && sid != null) {
      summary = await sm.summaryFor(sid);
    }

    final ctx = _assembler.assemble(
      systemPrompt: base,
      speakerName: _currentSpeaker,
      speakerNote: profile?.note,
      knowledge: knowledge,
      memories: memories,
      sessionSummary: summary,
      recentMessages: recentMessages,
    );
    _lastContext = ctx;
    return ctx.messages;
  }

  // ── 合成播放 ──────────────────────────────────────────────────────

  /// 声纹门禁的拒绝语(由 UI 按当前语言注入,服务本身拿不到 l10n)。
  String voiceprintGateReply = '抱歉,我无法确认你的身份,已停止对话。';

  /// 门禁拒绝:只播本地合成的拒绝语,不落库、不问 LLM。
  ///
  /// 复用 [_speakReply]:它已经处理了停麦(防自听反馈)、分块合成、
  /// 播完后 [_onPlaybackDrained] 恢复麦克风 —— 拒绝语不会被自己的麦克风
  /// 听到而再次触发。
  Future<void> _rejectByGate() async {
    await _stopMicStream();

    // 没有可用发音(比如克隆音被删了):静默拒绝,别把对话卡在 error。
    if (!_hasUsableVoice()) {
      _lastError = '未配置对话发音,门禁无法播报拒绝语';
      _phase = ConversationPhase.listening;
      notifyListeners();
      await _resumeMic();
      return;
    }

    await _speakReply(voiceprintGateReply);

    // 合成/播放失败时 _speakReply 内部会把 phase 置为 error 且不恢复麦克风,
    // 门禁不能因此把整个对话卡死:退回 listening 继续听。
    if (_phase == ConversationPhase.error) {
      _phase = ConversationPhase.listening;
      notifyListeners();
      await _resumeMic();
    }
  }

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
    // 说话人绑定的克隆音优先:谁说话就用谁的克隆音回。没绑(或绑的克隆音
    // 已被删)才回落到全局设置。
    final speaker = _currentSpeaker;
    if (speaker != null) {
      final bound = _voiceprint.profileOf(speaker)?.cloneId;
      if (bound != null && _cloning.byId(bound) != null) {
        return CloneVoice(cloneId: bound);
      }
    }
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
