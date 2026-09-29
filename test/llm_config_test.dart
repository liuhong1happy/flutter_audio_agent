/// 大模型配置:列表解析(种子化 / 迁移 / 回落)+ 编解码 + 服务商切换。
///
/// 这些是**纯函数**测试 —— 测试环境里 `dvaStore()` 恒为 null,走不到真正的
/// `TtsSettings.load()`,所以迁移与种子化逻辑必须抽成纯函数才能覆盖。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_tts_demo/data/models/llm_config.dart';

/// 造一条持久化形态的 Map。
Map<String, dynamic> item({
  String id = 'a1',
  String? name,
  String baseUrl = 'https://api.deepseek.com/v1',
  String apiKey = '',
  String model = 'deepseek-v4-flash',
  String systemPrompt = '',
}) =>
    <String, dynamic>{
      'id': id,
      'name': name ?? providerOfBaseUrl(baseUrl),
      'baseUrl': baseUrl,
      'apiKey': apiKey,
      'model': model,
      'systemPrompt': systemPrompt,
    };

void main() {
  group('resolveLlmConfigs', () {
    test('列表为空且无旧值 → 种一条内置默认(DeepSeek)', () {
      final (configs, active) = resolveLlmConfigs(
        items: const [],
        activeId: null,
        legacyBaseUrl: kDefaultLlmBaseUrl,
        legacyApiKey: '',
        legacyModel: kDefaultLlmModel,
        legacySystemPrompt: '',
      );

      expect(configs.length, 1);
      expect(configs.first.baseUrl, kDefaultLlmBaseUrl);
      expect(configs.first.model, kDefaultLlmModel);
      expect(configs.first.apiKey, isEmpty);
      expect(configs.first.isConfigured, isFalse);
      expect(active, configs.first.id, reason: 'activeId 必须命中列表');
    });

    test('列表为空但旧字段有实质内容 → 用旧值种一条(老用户升级)', () {
      final (configs, active) = resolveLlmConfigs(
        items: const [],
        activeId: null,
        legacyBaseUrl: 'https://api.moonshot.cn/v1',
        legacyApiKey: 'sk-old',
        legacyModel: 'moonshot-v1-8k',
        legacySystemPrompt: '你是猫娘',
      );

      expect(configs.length, 1);
      final c = configs.first;
      expect(c.baseUrl, 'https://api.moonshot.cn/v1');
      expect(c.apiKey, 'sk-old');
      expect(c.model, 'moonshot-v1-8k');
      expect(c.systemPrompt, '你是猫娘');
      expect(c.name, 'Moonshot (Kimi)', reason: '名称按 baseUrl 反查预设名');
      expect(c.isConfigured, isTrue);
      expect(active, c.id);
    });

    test('只改过地址、还没填 Key 的老用户也不该被丢', () {
      // 只看 apiKey 是否为空就判断"没配过"会把这类用户的自定义地址吞掉。
      final (configs, _) = resolveLlmConfigs(
        items: const [],
        activeId: null,
        legacyBaseUrl: 'https://my-proxy.example.com/v1',
        legacyApiKey: '',
        legacyModel: kDefaultLlmModel,
        legacySystemPrompt: '',
      );

      expect(configs.length, 1);
      expect(configs.first.baseUrl, 'https://my-proxy.example.com/v1');
      expect(configs.first.name, kCustomProvider, reason: '反查不到预设');
    });

    test('列表非空时忽略旧字段(列表优先)', () {
      final (configs, active) = resolveLlmConfigs(
        items: [item(id: 'x', apiKey: 'sk-new')],
        activeId: 'x',
        legacyBaseUrl: 'https://api.moonshot.cn/v1',
        legacyApiKey: 'sk-old',
        legacyModel: 'moonshot-v1-8k',
        legacySystemPrompt: '旧提示词',
      );

      expect(configs.length, 1);
      expect(configs.first.apiKey, 'sk-new');
      expect(active, 'x');
    });

    test('activeId 指向不存在的配置 → 回落到第一条', () {
      final (configs, active) = resolveLlmConfigs(
        items: [item(id: 'a'), item(id: 'b')],
        activeId: '不存在',
        legacyBaseUrl: kDefaultLlmBaseUrl,
        legacyApiKey: '',
        legacyModel: kDefaultLlmModel,
        legacySystemPrompt: '',
      );

      expect(configs.length, 2);
      expect(active, configs.first.id);
    });

    test('activeId 为 null → 回落到第一条', () {
      final (_, active) = resolveLlmConfigs(
        items: [item(id: 'a'), item(id: 'b')],
        activeId: null,
        legacyBaseUrl: kDefaultLlmBaseUrl,
        legacyApiKey: '',
        legacyModel: kDefaultLlmModel,
        legacySystemPrompt: '',
      );

      expect(active, 'a');
    });
  });

  group('LlmConfig', () {
    test('toMap/fromMap 六字段往返', () {
      const c = LlmConfig(
        id: 'i1',
        name: '工作',
        baseUrl: 'https://api.moonshot.cn/v1',
        apiKey: 'sk-x',
        model: 'moonshot-v1-8k',
        systemPrompt: '简洁回答',
      );

      final round = LlmConfig.fromMap(c.toMap());
      expect(round.id, 'i1');
      expect(round.name, '工作');
      expect(round.baseUrl, 'https://api.moonshot.cn/v1');
      expect(round.apiKey, 'sk-x');
      expect(round.model, 'moonshot-v1-8k');
      expect(round.systemPrompt, '简洁回答');
    });

    test('缺字段的旧数据按 baseUrl 反查补齐,不崩', () {
      final c = LlmConfig.fromMap({'id': 'z'});
      expect(c.baseUrl, kDefaultLlmBaseUrl);
      expect(c.model, kDefaultLlmModel);
      expect(c.name, 'DeepSeek');
      expect(c.apiKey, isEmpty);
    });

    test('服务商由 baseUrl 反查,不单独存', () {
      expect(
        const LlmConfig(
          id: 'i',
          name: 'n',
          baseUrl: 'https://api.deepseek.com/v1',
          apiKey: '',
          model: 'm',
        ).provider,
        'DeepSeek',
      );
      expect(
        const LlmConfig(
          id: 'i',
          name: 'n',
          baseUrl: 'https://whatever.example.com',
          apiKey: '',
          model: 'm',
        ).provider,
        kCustomProvider,
      );
    });

    test('withPreset 替换地址与模型;名称只在没被改过时才跟着换', () {
      final preset = presetByName('Moonshot (Kimi)')!;

      // 名称还是旧服务商名 → 视为用户没改过,跟着换。
      final fresh = LlmConfig.fromPreset('i', llmPresets.first);
      final switched = fresh.withPreset(preset);
      expect(switched.baseUrl, preset.baseUrl);
      expect(switched.model, preset.model);
      expect(switched.name, preset.name);

      // 用户起过名 → 不被覆盖。
      final renamed = fresh.copyWith(name: '我的千问');
      final switched2 = renamed.withPreset(preset);
      expect(switched2.name, '我的千问');
      expect(switched2.baseUrl, preset.baseUrl);
      expect(switched2.model, preset.model);
    });

    test('withPreset 保留 API Key 与系统提示词', () {
      final c = const LlmConfig(
        id: 'i',
        name: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: 'sk-keep',
        model: 'deepseek-v4-flash',
        systemPrompt: '保留我',
      );
      final switched = c.withPreset(presetByName('智谱 (GLM)')!);
      expect(switched.apiKey, 'sk-keep');
      expect(switched.systemPrompt, '保留我');
    });

    test('isConfigured 只看 Key 是否非空(空白不算)', () {
      expect(
        const LlmConfig(
          id: 'i',
          name: 'n',
          baseUrl: 'u',
          apiKey: '   ',
          model: 'm',
        ).isConfigured,
        isFalse,
      );
      expect(
        const LlmConfig(
          id: 'i',
          name: 'n',
          baseUrl: 'u',
          apiKey: 'k',
          model: 'm',
        ).isConfigured,
        isTrue,
      );
    });
  });
}
