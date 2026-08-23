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
        'name': '张三',
        'note': '同事',
        'embeddings': [
          [0.1, 0.2],
        ],
      },
    ];
    final rVp = VoiceprintsState()..fromJson(vp.toJson());
    expect(rVp.items.length, 1);
    expect(rVp.items.first['note'], '同事');

    final settings = SettingsState();
    settings.llmBaseUrl = 'https://api.deepseek.com/v1';
    settings.conversationVoiceType = 'clone';
    settings.conversationCloneId = 'c1';
    final rSettings = SettingsState()..fromJson(settings.toJson());
    expect(rSettings.llmBaseUrl, 'https://api.deepseek.com/v1');
    expect(rSettings.conversationVoiceType, 'clone');
    expect(rSettings.conversationCloneId, 'c1');
  });
}
