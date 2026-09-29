/// dva 状态(克隆/声纹/设置)JSON 序列化往返测试。
///
/// 会话历史已迁 SQLite,见 conversation_store_test.dart。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_tts_demo/data/dva/app_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Clones/Voiceprints/Settings JSON 往返', () {
    final clones = ClonesState();
    clones.items = [
      {
        'id': '1',
        'name': '声音',
        'referenceWavPath': '/a.wav',
        'sampleRate': 24000,
        'createdAt': 12345,
      },
    ];
    final rClones = ClonesState()..fromJson(clones.toJson());
    expect(rClones.items.length, 1);
    expect(rClones.items.first['name'], '声音');

    final vp = VoiceprintsState();
    vp.items = [
      {
        'modelId': 'm1',
        'name': '张三',
        'note': '同事',
        'cloneId': 'c9',
        'embeddings': [
          [0.1, 0.2],
        ],
      },
    ];
    final rVp = VoiceprintsState()..fromJson(vp.toJson());
    expect(rVp.items.length, 1);
    expect(rVp.items.first['note'], '同事');
    // 声纹档案带模型与克隆音绑定(items 是宽松 Map,无需改 VoiceprintsState)。
    expect(rVp.items.first['modelId'], 'm1');
    expect(rVp.items.first['cloneId'], 'c9');

    final settings = SettingsState();
    // 大模型改成列表后,这四个扁平字段是「启用项的镜像」(由 setLlmConfigs
    // reducer 写入)。这里把列表与镜像一起断言 —— 只断言 llmBaseUrl 会是**空转**:
    // 它的默认值恰好就是下面这个字符串,写不写都能过。
    settings.llmConfigs = [
      {
        'id': 'a1',
        'name': '工作',
        'baseUrl': 'https://api.moonshot.cn/v1',
        'apiKey': 'sk-a1',
        'model': 'moonshot-v1-8k',
        'systemPrompt': '简洁回答',
      },
      {
        'id': 'a2',
        'name': '个人',
        'baseUrl': 'https://api.deepseek.com/v1',
        'apiKey': 'sk-a2',
        'model': 'deepseek-v4-flash',
        'systemPrompt': '',
      },
    ];
    settings.activeLlmConfigId = 'a2';
    settings.conversationVoiceType = 'clone';
    settings.conversationCloneId = 'c1';
    settings.voiceprintModelId = 'm2';
    settings.voiceprintGateEnabled = true;
    settings.requireAuthForEnroll = false;
    final rSettings = SettingsState()..fromJson(settings.toJson());
    expect(rSettings.llmConfigs.length, 2);
    expect(rSettings.llmConfigs.first['name'], '工作');
    expect(rSettings.llmConfigs.last['systemPrompt'], '');
    expect(rSettings.activeLlmConfigId, 'a2');
    expect(rSettings.conversationVoiceType, 'clone');
    expect(rSettings.conversationCloneId, 'c1');
    expect(rSettings.voiceprintModelId, 'm2');
    expect(rSettings.voiceprintGateEnabled, isTrue);
    expect(rSettings.requireAuthForEnroll, isFalse);

    // 缺省值:门禁默认关,认证保护默认开。
    final dflt = SettingsState();
    expect(dflt.voiceprintGateEnabled, isFalse);
    expect(dflt.requireAuthForEnroll, isTrue);
    final rDflt = SettingsState()..fromJson(dflt.toJson());
    expect(rDflt.voiceprintGateEnabled, isFalse);
    expect(rDflt.requireAuthForEnroll, isTrue);

    // 全新用户的 LLM 配置列表为空 —— 种子化由 TtsSettings.load() 负责,
    // 不写进 SettingsState 的默认值(否则"新装 vs 迁移"就分不出来了)。
    expect(rDflt.llmConfigs, isEmpty);
    expect(rDflt.activeLlmConfigId, isNull);
  });

  test('大模型:旧版单配置的四个扁平字段仍能往返(迁移输入源)', () {
    // 列表为空时,TtsSettings.load() 会用这四个字段种出第一条配置。
    // 所以它们必须继续被持久化,否则老用户升级即丢配置。
    final legacy = SettingsState();
    legacy.llmBaseUrl = 'https://api.moonshot.cn/v1';
    legacy.llmApiKey = 'sk-legacy';
    legacy.llmModel = 'moonshot-v1-8k';
    legacy.llmSystemPrompt = '你是猫娘';

    final restored = SettingsState()..fromJson(legacy.toJson());
    expect(restored.llmConfigs, isEmpty, reason: '旧版没有列表');
    expect(restored.llmBaseUrl, 'https://api.moonshot.cn/v1');
    expect(restored.llmApiKey, 'sk-legacy');
    expect(restored.llmModel, 'moonshot-v1-8k');
    expect(restored.llmSystemPrompt, '你是猫娘');
  });
}
