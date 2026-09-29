/// 应用级 TTS 设置(对应需求:界面上自定义应用特定的 TTS)。
///
/// 运行时用 [ChangeNotifier] 驱动 UI;持久化交给 flutter_dva
/// (`settings` 模型 + ReduxPersistor)。dva 未初始化(测试环境)时
/// 读写自动跳过,保持本地默认值。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_dva/flutter_dva.dart';

import 'package:flutter_tts_demo/data/dva/app_dva.dart';
import 'package:flutter_tts_demo/data/dva/app_models.dart';
import 'package:flutter_tts_demo/data/models/llm_config.dart';

/// 对话发音方式:模型音色 或 克隆音。
enum ConversationVoiceType { model, clone }

class TtsSettings extends ChangeNotifier {
  /// 是否已从持久化恢复(仅首次 [load] 生效,后续调用为幂等 no-op)。
  ///
  /// 运行时以本 ChangeNotifier 为单一事实源;持久化(flutter_dva)只做
  /// 写入,避免"运行时改动被重复 load 覆盖"的漂移。
  bool _loaded = false;

  /// 当前选中的模型 id(未选择为 null)。
  String? _selectedModelId;
  String? get selectedModelId => _selectedModelId;

  /// 说话人 sid(多音色模型有效)。
  int _sid = 0;
  int get sid => _sid;

  /// 语速 0.5 ~ 2.0。
  double _speed = 1.0;
  double get speed => _speed;

  /// 句间静音比例。
  double _silenceScale = 0.2;
  double get silenceScale => _silenceScale;

  /// 引擎推理线程数。
  int _numThreads = 2;
  int get numThreads => _numThreads;

  /// 下载镜像前缀(空 = 直连 GitHub;国内网络慢时可切换镜像)。
  String _mirrorPrefix = '';
  String get mirrorPrefix => _mirrorPrefix;

  /// 朗读视图是否自动滚动跟随。
  bool _autoScroll = true;
  bool get autoScroll => _autoScroll;

  // ── 对话 / 克隆 / 声纹(新增)───────────────────────────────────────

  /// 大模型配置列表(至少一条)。写入走 [_persistLlmConfigs]。
  List<LlmConfig> _llmConfigs = [];
  List<LlmConfig> get llmConfigs => List.unmodifiable(_llmConfigs);

  /// 启用中的配置 id(为 null 或指向不存在的 id 时回落到第一条)。
  String? _activeLlmConfigId;
  String? get activeLlmConfigId => _activeLlmConfigId;

  /// 启用中的配置。
  LlmConfig? get activeLlmConfig {
    if (_llmConfigs.isEmpty) return null;
    final id = _activeLlmConfigId;
    if (id != null) {
      for (final c in _llmConfigs) {
        if (c.id == id) return c;
      }
    }
    return _llmConfigs.first;
  }

  /// 启用的配置是否可用(有非空 API Key)。
  bool get isLlmConfigured => activeLlmConfig?.isConfigured ?? false;

  // 下面四个是**兼容 getter**:解析"启用中的配置"。保持同名是为了让
  // LlmService / ConversationService 无需任何改动 —— 它们每次请求实时读
  // 这几个 getter,等于天然跟着启用项走。
  String get llmBaseUrl => activeLlmConfig?.baseUrl ?? '';
  String get llmApiKey => activeLlmConfig?.apiKey ?? '';
  String get llmModel => activeLlmConfig?.model ?? '';
  String get llmSystemPrompt => activeLlmConfig?.systemPrompt ?? '';

  /// 对话用的 ASR 模型 id(一键初始化时自动设置)。
  String? _asrModelId;
  String? get asrModelId => _asrModelId;

  /// 声纹识别阈值(0~1)。
  double _voiceprintThreshold = 0.6;
  double get voiceprintThreshold => _voiceprintThreshold;

  /// 当前声纹模型 id(录入页每次可选,记住上次选择)。
  ///
  /// 这里只存 id,不保证它对应的模型仍存在或已下载——解析与回落
  /// (取目录里首个已下载的声纹模型)由 VoiceprintService 负责,
  /// 与 asrModelId 的分工保持一致。
  String? _voiceprintModelId;
  String? get voiceprintModelId => _voiceprintModelId;

  /// 声纹门禁:开启后只有当前模型下注册过的说话人才能触发对话。
  ///
  /// ⚠️ 这是礼貌性门禁,不是安全边界:3 秒录音即可重放通过,本 app 自带的
  /// 声音克隆也能合成授权人声音,嵌入本身还是明文落盘。
  bool _voiceprintGateEnabled = false;
  bool get voiceprintGateEnabled => _voiceprintGateEnabled;

  /// 注册/删除声纹前是否要求设备认证(指纹 / 人脸 / PIN)。
  bool _requireAuthForEnroll = true;
  bool get requireAuthForEnroll => _requireAuthForEnroll;

  // ── 知识库检索(v1.0.2)────────────────────────────────────────────

  /// 当前文本嵌入模型 id。
  ///
  /// 只存 id,不保证它仍存在或已下载 —— 解析与回落(取目录里首个已下载的
  /// 嵌入模型)由 `KnowledgeService` 负责,与 `asrModelId`/`voiceprintModelId`
  /// 的分工保持一致。
  String? _embeddingModelId;
  String? get embeddingModelId => _embeddingModelId;

  /// 是否把检索到的知识库片段注入提示词。
  bool _kbEnabled = true;
  bool get kbEnabled => _kbEnabled;

  /// 注入的知识库片段数上限。
  int _kbTopK = 4;
  int get kbTopK => _kbTopK;

  /// 相似度阈值:低于它的片段**不注入**。
  ///
  /// ⚠️ **这是猜测值,须由真实语料实测校准**。设备实测同义句约 0.75–0.81、
  /// 异义句约 0.24–0.29,故 0.45 落在两者之间较靠下的位置(偏保守召回)。
  double _kbScoreThreshold = 0.45;
  double get kbScoreThreshold => _kbScoreThreshold;

  /// 长期记忆总开关。
  ///
  /// **默认开,但它会让每轮对话产生额外 LLM token 消耗**(抽取时要把最近若干轮
  /// 与已有记忆一起发给模型)—— 用户自付 API 费用,所以设置页必须说明。
  bool _memoryEnabled = true;
  bool get memoryEnabled => _memoryEnabled;

  /// 每攒够多少轮做一次记忆抽取。
  ///
  /// 单轮的上下文往往推不出稳定事实,批量更省也更准。
  int _memoryExtractInterval = 4;
  int get memoryExtractInterval => _memoryExtractInterval;

  /// 注入的长期记忆条数上限。
  int _memoryTopK = 6;
  int get memoryTopK => _memoryTopK;

  double _vadThreshold = 0.5;
  double get vadThreshold => _vadThreshold;

  double _vadMinSilence = 0.5;
  double get vadMinSilence => _vadMinSilence;

  double _vadMaxSpeech = 15.0;
  double get vadMaxSpeech => _vadMaxSpeech;

  ConversationVoiceType _conversationVoiceType = ConversationVoiceType.model;
  ConversationVoiceType get conversationVoiceType => _conversationVoiceType;

  String? _conversationModelVoiceId;
  String? get conversationModelVoiceId => _conversationModelVoiceId;

  String? _conversationCloneId;
  String? get conversationCloneId => _conversationCloneId;

  int _conversationSid = 0;
  int get conversationSid => _conversationSid;

  /// 从 dva store 恢复持久化设置(仅首次调用生效)。
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final store = dvaStore();
    // 旧版单配置的四个扁平字段:只在"新列表为空"时作为迁移输入。
    var legacyBaseUrl = kDefaultLlmBaseUrl;
    var legacyApiKey = '';
    var legacyModel = kDefaultLlmModel;
    var legacySystemPrompt = '';
    var rawItems = <Map<String, dynamic>>[];
    if (store != null) {
      final s = store.getStateByKey<SettingsState>('settings');
      rawItems = s.llmConfigs;
      legacyBaseUrl = s.llmBaseUrl;
      legacyApiKey = s.llmApiKey;
      legacyModel = s.llmModel;
      legacySystemPrompt = s.llmSystemPrompt;
      _selectedModelId = s.selectedModelId;
      _sid = s.sid;
      _speed = s.speed;
      _silenceScale = s.silenceScale;
      _numThreads = s.numThreads;
      _mirrorPrefix = s.mirrorPrefix;
      _autoScroll = s.autoScroll;
      _asrModelId = s.asrModelId;
      _voiceprintThreshold = s.voiceprintThreshold;
      _voiceprintModelId = s.voiceprintModelId;
      _voiceprintGateEnabled = s.voiceprintGateEnabled;
      _requireAuthForEnroll = s.requireAuthForEnroll;
      _embeddingModelId = s.embeddingModelId;
      _kbEnabled = s.kbEnabled;
      _kbTopK = s.kbTopK;
      _kbScoreThreshold = s.kbScoreThreshold;
      _memoryEnabled = s.memoryEnabled;
      _memoryExtractInterval = s.memoryExtractInterval;
      _memoryTopK = s.memoryTopK;
      _vadThreshold = s.vadThreshold;
      _vadMinSilence = s.vadMinSilence;
      _vadMaxSpeech = s.vadMaxSpeech;
      _conversationVoiceType = s.conversationVoiceType == 'clone'
          ? ConversationVoiceType.clone
          : ConversationVoiceType.model;
      _conversationModelVoiceId = s.conversationModelVoiceId;
      _conversationCloneId = s.conversationCloneId;
      _conversationSid = s.conversationSid;
    }
    // 大模型配置的解析刻意放在 store 判断**之外**:测试环境无 dva store,
    // 但"恒有 ≥1 条配置"是 TtsSettings 自身的不变量,不该依赖持久化存在。
    final resolved = resolveLlmConfigs(
      items: rawItems,
      activeId: _activeLlmConfigId,
      legacyBaseUrl: legacyBaseUrl,
      legacyApiKey: legacyApiKey,
      legacyModel: legacyModel,
      legacySystemPrompt: legacySystemPrompt,
    );
    _llmConfigs = resolved.$1;
    _activeLlmConfigId = resolved.$2;
    notifyListeners();
  }

  Future<void> _dispatch(String type, dynamic payload) async {
    final store = dvaStore();
    if (store != null) {
      await store.dispatch(DvaAction(type, payload));
    }
  }

  Future<void> selectModel(String? modelId) async {
    _selectedModelId = modelId;
    _sid = 0;
    notifyListeners();
    await _dispatch('settings/selectModel', modelId);
    await _dispatch('settings/setSid', 0);
  }

  Future<void> setSid(int value) async {
    _sid = value;
    notifyListeners();
    await _dispatch('settings/setSid', value);
  }

  Future<void> setSpeed(double value) async {
    _speed = value;
    notifyListeners();
    await _dispatch('settings/setSpeed', value);
  }

  Future<void> setSilenceScale(double value) async {
    _silenceScale = value;
    notifyListeners();
    await _dispatch('settings/setSilenceScale', value);
  }

  Future<void> setNumThreads(int value) async {
    _numThreads = value;
    notifyListeners();
    await _dispatch('settings/setNumThreads', value);
  }

  Future<void> setMirrorPrefix(String value) async {
    _mirrorPrefix = value;
    notifyListeners();
    await _dispatch('settings/setMirrorPrefix', value);
  }

  Future<void> setAutoScroll(bool value) async {
    _autoScroll = value;
    notifyListeners();
    await _dispatch('settings/setAutoScroll', value);
  }

  // ── 对话 / 克隆 / 声纹 setter(新增)────────────────────────────────

  // 下面四个是**兼容 setter**:写"启用中的配置"的对应字段。若当前一条配置都
  // 没有,先种子化一条 —— 测试与老代码里的 `setLlmApiKey('k')` 因此无需改写。

  Future<void> setLlmBaseUrl(String value) =>
      _updateActiveConfig((c) => c.copyWith(baseUrl: value));

  Future<void> setLlmApiKey(String value) =>
      _updateActiveConfig((c) => c.copyWith(apiKey: value));

  Future<void> setLlmModel(String value) =>
      _updateActiveConfig((c) => c.copyWith(model: value));

  Future<void> setLlmSystemPrompt(String value) =>
      _updateActiveConfig((c) => c.copyWith(systemPrompt: value));

  // ── 大模型配置列表管理 ────────────────────────────────────────────

  /// 保证至少有一条配置(空则种一条内置默认)。返回启用项的 id。
  String _ensureConfigs() {
    if (_llmConfigs.isEmpty) {
      _llmConfigs = [LlmConfig.fromPreset('default', llmPresets.first)];
      _activeLlmConfigId = _llmConfigs.first.id;
    }
    if (!_llmConfigs.any((c) => c.id == _activeLlmConfigId)) {
      _activeLlmConfigId = _llmConfigs.first.id;
    }
    return _activeLlmConfigId!;
  }

  Future<void> _updateActiveConfig(LlmConfig Function(LlmConfig) change) async {
    final id = _ensureConfigs();
    _llmConfigs = [
      for (final c in _llmConfigs) if (c.id == id) change(c) else c,
    ];
    notifyListeners();
    await _persistLlmConfigs();
  }

  /// 启用某条配置。
  Future<void> setActiveLlmConfig(String id) async {
    if (!_llmConfigs.any((c) => c.id == id)) return;
    _activeLlmConfigId = id;
    notifyListeners();
    await _persistLlmConfigs();
  }

  /// 新增或覆盖一条配置(按 id 匹配)。
  Future<void> upsertLlmConfig(LlmConfig config) async {
    final exists = _llmConfigs.any((c) => c.id == config.id);
    _llmConfigs = exists
        ? [for (final c in _llmConfigs) if (c.id == config.id) config else c]
        : [..._llmConfigs, config];
    _ensureConfigs();
    notifyListeners();
    await _persistLlmConfigs();
  }

  /// 删除一条配置。**至少保留一条** —— 只剩一条时是 no-op。
  Future<void> deleteLlmConfig(String id) async {
    if (_llmConfigs.length <= 1) return;
    _llmConfigs = _llmConfigs.where((c) => c.id != id).toList();
    _ensureConfigs();
    notifyListeners();
    await _persistLlmConfigs();
  }

  Future<void> _persistLlmConfigs() async {
    await _dispatch('settings/setLlmConfigs', <String, dynamic>{
      'items': _llmConfigs.map((c) => c.toMap()).toList(),
      'activeId': _activeLlmConfigId,
    });
  }

  Future<void> setAsrModelId(String? value) async {
    _asrModelId = value;
    notifyListeners();
    await _dispatch('settings/setAsrModelId', value);
  }

  Future<void> setVoiceprintThreshold(double value) async {
    _voiceprintThreshold = value;
    notifyListeners();
    await _dispatch('settings/setVoiceprintThreshold', value);
  }

  /// 切换当前声纹模型(录入页选择后调用,即为"记住上次选择")。
  Future<void> setVoiceprintModelId(String? value) async {
    _voiceprintModelId = value;
    notifyListeners();
    await _dispatch('settings/setVoiceprintModelId', value);
  }

  Future<void> setVoiceprintGateEnabled(bool value) async {
    _voiceprintGateEnabled = value;
    notifyListeners();
    await _dispatch('settings/setVoiceprintGateEnabled', value);
  }

  Future<void> setRequireAuthForEnroll(bool value) async {
    _requireAuthForEnroll = value;
    notifyListeners();
    await _dispatch('settings/setRequireAuthForEnroll', value);
  }

  /// 切换当前嵌入模型。
  ///
  /// 换模型**会自动触发索引重建**:旧向量的 `model_id` 与新模型不符,
  /// 会被 [KnowledgeStore.pendingChunks] 视作"待回填"。这是刻意的 ——
  /// 两个模型的向量不可比(且维度相同、混用不报错),必须重算而不是复用。
  Future<void> setEmbeddingModelId(String? value) async {
    _embeddingModelId = value;
    notifyListeners();
    await _dispatch('settings/setEmbeddingModelId', value);
  }

  Future<void> setKbEnabled(bool value) async {
    _kbEnabled = value;
    notifyListeners();
    await _dispatch('settings/setKbEnabled', value);
  }

  Future<void> setKbTopK(int value) async {
    _kbTopK = value;
    notifyListeners();
    await _dispatch('settings/setKbTopK', value);
  }

  Future<void> setKbScoreThreshold(double value) async {
    _kbScoreThreshold = value;
    notifyListeners();
    await _dispatch('settings/setKbScoreThreshold', value);
  }

  Future<void> setMemoryEnabled(bool value) async {
    _memoryEnabled = value;
    notifyListeners();
    await _dispatch('settings/setMemoryEnabled', value);
  }

  Future<void> setMemoryExtractInterval(int value) async {
    _memoryExtractInterval = value;
    notifyListeners();
    await _dispatch('settings/setMemoryExtractInterval', value);
  }

  Future<void> setMemoryTopK(int value) async {
    _memoryTopK = value;
    notifyListeners();
    await _dispatch('settings/setMemoryTopK', value);
  }

  Future<void> setVadThreshold(double value) async {
    _vadThreshold = value;
    notifyListeners();
    await _dispatch('settings/setVadThreshold', value);
  }

  Future<void> setVadMinSilence(double value) async {
    _vadMinSilence = value;
    notifyListeners();
    await _dispatch('settings/setVadMinSilence', value);
  }

  Future<void> setVadMaxSpeech(double value) async {
    _vadMaxSpeech = value;
    notifyListeners();
    await _dispatch('settings/setVadMaxSpeech', value);
  }

  /// 选择模型音色作为对话发音。
  Future<void> setConversationVoiceModel(String? modelId, int sid) async {
    _conversationVoiceType = ConversationVoiceType.model;
    _conversationModelVoiceId = modelId;
    _conversationSid = sid;
    notifyListeners();
    await _dispatch('settings/setConversationVoiceModel', [modelId, sid]);
  }

  /// 选择克隆音作为对话发音。
  Future<void> setConversationVoiceClone(String? cloneId) async {
    _conversationVoiceType = ConversationVoiceType.clone;
    _conversationCloneId = cloneId;
    notifyListeners();
    await _dispatch('settings/setConversationVoiceClone', cloneId);
  }
}
