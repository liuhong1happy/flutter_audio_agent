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

  /// LLM 服务基地址(OpenAI 兼容)。
  String _llmBaseUrl = 'https://api.deepseek.com/v1';
  String get llmBaseUrl => _llmBaseUrl;

  String _llmApiKey = '';
  String get llmApiKey => _llmApiKey;

  /// LLM 模型 id(DeepSeek 为 deepseek-v4-flash / deepseek-v4-pro)。
  String _llmModel = 'deepseek-v4-flash';
  String get llmModel => _llmModel;

  String _llmSystemPrompt = '';
  String get llmSystemPrompt => _llmSystemPrompt;

  /// 对话用的 ASR 模型 id(一键初始化时自动设置)。
  String? _asrModelId;
  String? get asrModelId => _asrModelId;

  /// 声纹识别阈值(0~1)。
  double _voiceprintThreshold = 0.6;
  double get voiceprintThreshold => _voiceprintThreshold;

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
    if (store != null) {
      final s = store.getStateByKey<SettingsState>('settings');
      _selectedModelId = s.selectedModelId;
      _sid = s.sid;
      _speed = s.speed;
      _silenceScale = s.silenceScale;
      _numThreads = s.numThreads;
      _mirrorPrefix = s.mirrorPrefix;
      _autoScroll = s.autoScroll;
      _llmBaseUrl = s.llmBaseUrl;
      _llmApiKey = s.llmApiKey;
      _llmModel = s.llmModel;
      _llmSystemPrompt = s.llmSystemPrompt;
      _asrModelId = s.asrModelId;
      _voiceprintThreshold = s.voiceprintThreshold;
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

  Future<void> setLlmBaseUrl(String value) async {
    _llmBaseUrl = value;
    notifyListeners();
    await _dispatch('settings/setLlmBaseUrl', value);
  }

  Future<void> setLlmApiKey(String value) async {
    _llmApiKey = value;
    notifyListeners();
    await _dispatch('settings/setLlmApiKey', value);
  }

  Future<void> setLlmModel(String value) async {
    _llmModel = value;
    notifyListeners();
    await _dispatch('settings/setLlmModel', value);
  }

  Future<void> setLlmSystemPrompt(String value) async {
    _llmSystemPrompt = value;
    notifyListeners();
    await _dispatch('settings/setLlmSystemPrompt', value);
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
