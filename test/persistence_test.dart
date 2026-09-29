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
    settings.llmBaseUrl = 'https://api.deepseek.com/v1';
    settings.conversationVoiceType = 'clone';
    settings.conversationCloneId = 'c1';
    settings.voiceprintModelId = 'm2';
    settings.voiceprintGateEnabled = true;
    settings.requireAuthForEnroll = false;
    final rSettings = SettingsState()..fromJson(settings.toJson());
    expect(rSettings.llmBaseUrl, 'https://api.deepseek.com/v1');
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
  });
}
