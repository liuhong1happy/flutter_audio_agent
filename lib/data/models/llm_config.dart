/// 大模型(LLM)配置:一条 = 一套 地址 + Key + 模型 + 系统提示词。
///
/// 用户可以逐条添加多套配置(比如 DeepSeek 和通义千问各一条),其中**一条启用**
/// 为默认;实际请求只走启用那条([TtsSettings.activeLlmConfig])。
///
/// 持久化沿用本仓库对"列表型数据"的既有做法:存宽松的
/// `List<Map<String, dynamic>>`(见 `SettingsState.llmConfigs`),由这里的
/// [LlmConfig.toMap]/[LlmConfig.fromMap] 做编解码。
library;

import 'package:flutter/foundation.dart';

/// 内置默认大模型(与旧版单配置的默认值一致)。
const String kDefaultLlmBaseUrl = 'https://api.deepseek.com/v1';
const String kDefaultLlmModel = 'deepseek-v4-flash';

/// OpenAI 兼容服务商预设:选中即替换配置里的地址与默认模型。
@immutable
class LlmProviderPreset {
  const LlmProviderPreset({
    required this.name,
    required this.baseUrl,
    required this.model,
  });

  final String name;
  final String baseUrl;
  final String model;
}

const List<LlmProviderPreset> llmPresets = [
  LlmProviderPreset(
    name: 'DeepSeek',
    baseUrl: kDefaultLlmBaseUrl,
    model: kDefaultLlmModel,
  ),
  LlmProviderPreset(
    name: 'Moonshot (Kimi)',
    baseUrl: 'https://api.moonshot.cn/v1',
    model: 'moonshot-v1-8k',
  ),
  LlmProviderPreset(
    name: '智谱 (GLM)',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    model: 'glm-4-flash',
  ),
  LlmProviderPreset(
    name: '通义千问 (Qwen)',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    model: 'qwen-plus',
  ),
];

/// 自定义服务商:地址与模型完全由用户填,选它不覆盖任何字段。
const String kCustomProvider = 'custom';

/// 按 baseUrl 反查预设名(匹配不上返回 [kCustomProvider])。
///
/// 服务商**不单独存字段** —— baseUrl 是唯一真相,再存一份就多一处可能漂移的
/// 状态。下拉框的当前值就靠这个反查。
String providerOfBaseUrl(String baseUrl) {
  for (final p in llmPresets) {
    if (p.baseUrl == baseUrl) return p.name;
  }
  return kCustomProvider;
}

/// 按名字取预设(找不到返回 null)。
LlmProviderPreset? presetByName(String name) {
  for (final p in llmPresets) {
    if (p.name == name) return p;
  }
  return null;
}

@immutable
class LlmConfig {
  const LlmConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.systemPrompt = '',
  });

  factory LlmConfig.fromMap(Map<String, dynamic> json) {
    final baseUrl = json['baseUrl'] as String? ?? kDefaultLlmBaseUrl;
    final name = json['name'] as String? ?? '';
    return LlmConfig(
      id: json['id'] as String? ?? '',
      name: name.isEmpty ? providerOfBaseUrl(baseUrl) : name,
      baseUrl: baseUrl,
      apiKey: json['apiKey'] as String? ?? '',
      model: json['model'] as String? ?? kDefaultLlmModel,
      systemPrompt: json['systemPrompt'] as String? ?? '',
    );
  }

  /// 以某个预设为初值新建一条配置([id] 由调用方给)。
  factory LlmConfig.fromPreset(String id, LlmProviderPreset preset) =>
      LlmConfig(
        id: id,
        name: preset.name,
        baseUrl: preset.baseUrl,
        apiKey: '',
        model: preset.model,
      );

  final String id;

  /// 用户可改的显示名(新建时默认取服务商名)。
  final String name;

  final String baseUrl;
  final String apiKey;
  final String model;

  /// 该配置专用的系统提示词;空 = 用内置默认提示词。
  final String systemPrompt;

  /// 服务商(由 baseUrl 反查,不单独存)。
  String get provider => providerOfBaseUrl(baseUrl);

  /// 是否可用(有非空 API Key)。
  bool get isConfigured => apiKey.trim().isNotEmpty;

  /// 副标题:`服务商 · 模型`。
  String get subtitle => '$provider · $model';

  LlmConfig copyWith({
    String? name,
    String? baseUrl,
    String? apiKey,
    String? model,
    String? systemPrompt,
  }) =>
      LlmConfig(
        id: id,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        systemPrompt: systemPrompt ?? this.systemPrompt,
      );

  /// 切换服务商:替换地址与默认模型(用户明确要求的行为)。
  ///
  /// 名称只在"仍等于旧服务商名"(即用户没改过)时才跟着换 —— 用户自己起的名
  /// 不被覆盖。
  LlmConfig withPreset(LlmProviderPreset preset) => LlmConfig(
        id: id,
        name: name == provider ? preset.name : name,
        baseUrl: preset.baseUrl,
        apiKey: apiKey,
        model: preset.model,
        systemPrompt: systemPrompt,
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'systemPrompt': systemPrompt,
      };
}

/// 解析持久化的配置列表,保证两条不变量:**恒有 ≥1 条配置**、**activeId 恒命中**。
///
/// 做成顶层纯函数(而不是 [TtsSettings] 的私有方法)是为了可测:测试环境里
/// `dvaStore()` 恒为 null,走不到真正的 `load()`,只有纯函数能被直接单测。
///
/// 迁移规则:
/// - 列表非空 → 用列表,忽略旧的扁平字段(**列表优先**)。
/// - 列表为空且旧字段有实质内容 → 用旧字段种一条(老用户升级路径)。
/// - 都没有 → 种一条内置默认(DeepSeek 预设)。
(List<LlmConfig>, String) resolveLlmConfigs({
  required List<Map<String, dynamic>> items,
  required String? activeId,
  required String legacyBaseUrl,
  required String legacyApiKey,
  required String legacyModel,
  required String legacySystemPrompt,
}) {
  var configs = items.map(LlmConfig.fromMap).toList();

  if (configs.isEmpty) {
    // 旧字段是否"有实质内容"。不能只看 apiKey —— 只改过地址还没填 Key 的
    // 用户同样属于"配过",丢掉他的地址就是回归。
    final hasLegacy = legacyApiKey.isNotEmpty ||
        legacySystemPrompt.isNotEmpty ||
        legacyBaseUrl != kDefaultLlmBaseUrl ||
        legacyModel != kDefaultLlmModel;
    configs = [
      if (hasLegacy)
        LlmConfig(
          id: 'legacy',
          name: providerOfBaseUrl(legacyBaseUrl),
          baseUrl: legacyBaseUrl,
          apiKey: legacyApiKey,
          model: legacyModel,
          systemPrompt: legacySystemPrompt,
        )
      else
        LlmConfig.fromPreset('default', llmPresets.first),
    ];
  }

  final active = configs.any((c) => c.id == activeId)
      ? activeId!
      : configs.first.id;
  return (configs, active);
}
