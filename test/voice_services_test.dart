/// 克隆 + 声纹服务测试(假引擎):档案增删、合成、注册/识别/删除/清空。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tts_demo/data/app_dependencies.dart';
import 'package:flutter_tts_demo/data/archive_extractor.dart';
import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/utils/text_chunker.dart';
import 'package:flutter_tts_demo/utils/wav_encoder.dart';

import 'support/fakes.dart';

Future<(AppDependencies, Directory)> _deps() async {
  SharedPreferences.setMockInitialValues({});
  final tempDir = Directory.systemTemp.createTempSync('svc_');
  final deps = AppDependencies(
    appLock: FakeAppLockService(),
    engine: FakeTtsEngine(segmentDuration: Duration.zero),
    downloader: FakeModelDownloader(),
    chunker: TextChunker(enableJieba: false),
    extractor: const ArchiveExtractor(useCompute: false),
    player: FakeAudioPlaybackQueue(),
    micRecorder: FakeMicRecorder(),
    vadEngine: FakeVadEngine(),
    asrEngine: FakeAsrEngine(),
    speakerEngine: FakeSpeakerEngine(),
    pocketEngine: FakePocketTtsEngine(),
    llmClient: FakeLlmClient(),
    conversationPlayer: FakeAudioPlaybackQueue(),
    conversationStore: MemoryConversationStore(),
    modelsDirProvider: () async => Directory('${tempDir.path}/models'),
    audioCacheDirProvider: () async => Directory('${tempDir.path}/audio'),
    cloneRefsDirProvider: () async => Directory('${tempDir.path}/clone_refs'),
  );
  await deps.init();
  addTearDown(() async {
    await deps.streamingService.disposeAll();
    deps.conversationService.dispose();
    tempDir.deleteSync(recursive: true);
  });
  return (deps, tempDir);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('克隆:createProfile → synthesize → delete → clear', () async {
    final (deps, tempDir) = await _deps();
    final wavPath = '${tempDir.path}/ref.wav';
    File(wavPath).writeAsBytesSync(
      wavBytes(Float32List.fromList([0.0, 0.5, -0.5]), 24000),
    );

    final profile = await deps.voiceCloningService.createProfile('我的声音', wavPath);
    expect(deps.voiceCloningService.profiles.length, 1);
    expect(profile.sampleRate, 24000);

    // 合成一段(假 Pocket 引擎返回静音)。
    final audio = await deps.voiceCloningService.synthesize('你好', profile);
    expect(audio.sampleRate, 16000);
    expect(audio.samples, isNotEmpty);

    await deps.voiceCloningService.deleteProfile(profile.id);
    expect(deps.voiceCloningService.profiles, isEmpty);

    // clearAll 幂等。
    await deps.voiceCloningService.clearAll();
    expect(deps.voiceCloningService.profiles, isEmpty);
  });

  test('声纹:enroll → identify → remove → clear', () async {
    final (deps, _) = await _deps();
    await deps.modelManager
        .downloadModel(ModelCatalog.byId(kLegacyVoiceprintModelId)!);

    await deps.voiceprintService.enroll(
      name: '张三',
      note: '同事',
      samples: [Float32List(160), Float32List(160)],
    );
    expect(deps.voiceprintService.profiles.length, 1);
    expect(deps.voiceprintService.profileOf('张三')?.note, '同事');

    // 识别路由已在 conversation_service_test 覆盖;这里验证档案查询。
    expect(deps.voiceprintService.hasProfiles, isTrue);

    await deps.voiceprintService.remove('张三');
    expect(deps.voiceprintService.profiles, isEmpty);

    await deps.voiceprintService.clearAll();
    expect(deps.voiceprintService.profiles, isEmpty);
  });
}
