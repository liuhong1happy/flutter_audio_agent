/// 声纹多模型:档案按模型隔离、识别不串模型、切换后重同步、编解码往返。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tts_demo/data/app_dependencies.dart';
import 'package:flutter_tts_demo/data/archive_extractor.dart';
import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/data/models/tts_model.dart';
import 'package:flutter_tts_demo/utils/text_chunker.dart';
import 'package:flutter_tts_demo/utils/voiceprint_service.dart';

import 'support/fakes.dart';

/// 两个声纹模型 id(A = 老模型 ERes2Net,B = CAMPPlus)。
const String kA = kLegacyVoiceprintModelId;
const String kB = '3dspeaker_speech_campplus_sv_zh-cn_16k-common';

Future<(AppDependencies, FakeSpeakerEngine)> _deps() async {
  SharedPreferences.setMockInitialValues({});
  final tempDir = Directory.systemTemp.createTempSync('vpm_');
  final speaker = FakeSpeakerEngine();
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
    speakerEngine: speaker,
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
  return (deps, speaker);
}

Future<void> _downloadBoth(AppDependencies deps) async {
  await deps.modelManager.downloadModel(ModelCatalog.byId(kA)!);
  await deps.modelManager.downloadModel(ModelCatalog.byId(kB)!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('目录:两个声纹模型,声明序首个仍是老模型(默认不变)', () {
    final speakers = ModelCatalog.speakers();
    expect(speakers.length, 2);
    expect(speakers.first.id, kA);
    expect(speakers[1].id, kB);
    // byKind 取声明序首个 —— 必须还是老模型,否则未选过模型的用户会静默换模型。
    expect(ModelCatalog.byKind(ModelKind.speaker)!.id, kA);
    expect(speakers[1].rawFileName, '$kB.onnx');
    expect(speakers[1].downloadFormat, ModelDownloadFormat.rawFile);
  });

  test('档案隔离:同一个名字在两个模型下各存各的,互不可见', () async {
    final (deps, speaker) = await _deps();
    await _downloadBoth(deps);
    final svc = deps.voiceprintService;

    await deps.settings.setVoiceprintModelId(kA);
    await svc.enroll(
      name: '张三',
      note: '同事',
      samples: [Float32List(160)],
    );
    expect(svc.profileOf('张三')?.note, '同事');
    expect(svc.currentModelId, kA);

    // 切到 B:管理列表里看不到 A 的档案。
    await deps.settings.setVoiceprintModelId(kB);
    expect(svc.currentModelId, kB);
    expect(svc.profiles, isEmpty);
    expect(svc.hasProfiles, isFalse);
    expect(svc.countOf(kB), 0);
    // 但 profileOf 跨桶兜底(对话流程取备注用),仍找得到 A 的那份。
    expect(svc.profileOf('张三')?.note, '同事');
    // 门禁的 fail-closed 判据也必须是"任何模型下"——否则只注册在 A 的人
    // 在当前模型是 B 时会被误挡(而 identify 明明认得出他)。
    expect(svc.hasAnyProfiles, isTrue);

    // 同名在 B 下注册,内容互不影响。
    await svc.enroll(
      name: '张三',
      note: '陌生人',
      samples: [Float32List(160)],
    );
    expect(svc.profileOf('张三')?.note, '陌生人');

    // 切回 A:还是原来那份。
    await deps.settings.setVoiceprintModelId(kA);
    expect(svc.profileOf('张三')?.note, '同事');
    expect(svc.countOf(kA), 1);
    expect(svc.countOf(kB), 1);
    expect(svc.modelIdsWithProfiles..sort(), [kA, kB]..sort());

    // 两个模型各自收到了自己的注册调用。
    expect(speaker.addedByModel[kA], ['张三']);
    expect(speaker.addedByModel[kB], ['张三']);
  });

  test('识别是跨模型并集:在 A 注册的人,当前模型是 B 时也认得出', () async {
    final (deps, speaker) = await _deps();
    await _downloadBoth(deps);
    final svc = deps.voiceprintService;

    await deps.settings.setVoiceprintModelId(kA);
    await svc.enroll(name: '张三', note: '同事', samples: [Float32List(160)]);
    speaker.nextNameByModel[kA] = '张三';

    expect(await svc.identify(Float32List(160), 16000), '张三');

    // 切到 B:B 自己没有档案,但 A 有 → 并集里仍然命中。
    // 这正是"两个模型都跑"换来的好处:在哪个模型下注册都认得出。
    await deps.settings.setVoiceprintModelId(kB);
    expect(await svc.identify(Float32List(160), 16000), '张三');
    // 备注也跟着找得到(否则会出现"认出了人却不注入备注")。
    expect(svc.profileOf('张三')?.note, '同事');
    // 但管理页的列表仍只显示当前模型(B)的档案。
    expect(svc.profiles, isEmpty);

    // 只跑"有档案"的模型:B 一个档案都没有,不该为它加载 onnx 白耗算力。
    expect(speaker.loadCalls, [kA]);
  });

  test('识别:两个模型都跑,同名直接返回,异名以当前模型为准', () async {
    final (deps, speaker) = await _deps();
    await _downloadBoth(deps);
    final svc = deps.voiceprintService;

    await deps.settings.setVoiceprintModelId(kA);
    await svc.enroll(name: '张三', note: '', samples: [Float32List(160)]);
    await deps.settings.setVoiceprintModelId(kB);
    await svc.enroll(name: '李四', note: '', samples: [Float32List(160)]);

    // 两个模型都命中同一名字 → 直接返回。
    speaker.nextNameByModel[kA] = '王五';
    speaker.nextNameByModel[kB] = '王五';
    expect(await svc.identify(Float32List(160), 16000), '王五');

    // 命中不同名字 → 当前模型(B)优先。
    speaker.nextNameByModel[kA] = '张三';
    speaker.nextNameByModel[kB] = '李四';
    expect(await svc.identify(Float32List(160), 16000), '李四');
    expect(speaker.loadCalls, containsAll([kA, kB]));
  });

  test('切换模型会重新加载并全量重同步,重复 ensureLoaded 不重复 load', () async {
    final (deps, speaker) = await _deps();
    await _downloadBoth(deps);
    final svc = deps.voiceprintService;

    await deps.settings.setVoiceprintModelId(kA);
    await svc.enroll(name: '张三', note: '', samples: [Float32List(160)]);
    await deps.settings.setVoiceprintModelId(kB);
    await svc.enroll(name: '李四', note: '', samples: [Float32List(160)]);
    await deps.settings.setVoiceprintModelId(kA);

    // 幂等:A 已就绪,切回来不该再 load。
    await svc.ensureLoaded();
    await svc.ensureLoaded();
    expect(speaker.loadCalls.where((id) => id == kA).length, 1);

    // 二次 load(模拟引擎重建)后档案要重新灌进去。
    await deps.settings.setVoiceprintModelId(kB);
    await svc.ensureLoaded();
    expect(speaker.addedByModel[kB], ['李四']);
  });

  test('没有任何已下载的声纹模型:currentModelId 为 null,识别空,注册报错', () async {
    final (deps, _) = await _deps();
    final svc = deps.voiceprintService;

    expect(svc.currentModelId, isNull);
    expect(svc.downloadedSpeakerModels, isEmpty);
    expect(svc.profiles, isEmpty);
    expect(await svc.identify(Float32List(160), 16000), '');

    await expectLater(
      svc.enroll(name: '张三', note: '', samples: [Float32List(160)]),
      throwsA(isA<StateError>()),
    );
  });

  test('设置指向已删除的模型:回落到首个已下载的声纹模型', () async {
    final (deps, _) = await _deps();
    await _downloadBoth(deps);
    final svc = deps.voiceprintService;

    await deps.settings.setVoiceprintModelId(kB);
    expect(svc.currentModelId, kB);

    await deps.modelManager.removeModel(ModelCatalog.byId(kB)!);
    expect(svc.currentModelId, kA);
  });

  test('纯函数:编解码往返 + 老数据迁到 kLegacyVoiceprintModelId', () {
    final byModel = {
      kA: {
        '张三': VoiceprintProfile(
          modelId: kA,
          name: '张三',
          note: '同事',
          embeddings: [Float32List.fromList([0.1, 0.2])],
          cloneId: 'c1',
        ),
      },
      kB: {
        '李四': VoiceprintProfile(
          modelId: kB,
          name: '李四',
          note: '',
          embeddings: [Float32List.fromList([0.3])],
        ),
      },
    };

    final round = VoiceprintService.decodeItems(
      VoiceprintService.encodeProfiles(byModel),
    );
    expect(round.keys.toSet(), {kA, kB});
    expect(round[kA]!['张三']!.note, '同事');
    expect(round[kA]!['张三']!.cloneId, 'c1');
    // 走了一趟 Float32,只比数量与量级。
    expect(round[kA]!['张三']!.embeddings.first.length, 2);
    expect(round[kA]!['张三']!.embeddings.first[0], closeTo(0.1, 1e-6));
    expect(round[kB]!['李四']!.cloneId, isNull);

    // 老数据没有 modelId → 归入老模型(不能用声明序猜)。
    final legacy = VoiceprintService.decodeItems([
      {
        'name': '老王',
        'note': '',
        'embeddings': [
          [0.5, 0.5],
        ],
      },
    ]);
    expect(legacy.keys.single, kLegacyVoiceprintModelId);
    expect(legacy[kLegacyVoiceprintModelId]!['老王']!.name, '老王');

    // 空名字 / 空嵌入被丢弃(保持原有语义)。
    expect(
      VoiceprintService.decodeItems([
        {'name': '', 'embeddings': [
          [1.0],
        ]},
        {'name': 'x', 'embeddings': <dynamic>[]},
      ]),
      isEmpty,
    );
  });

  test('绑定克隆音:写入档案并可解绑', () async {
    final (deps, _) = await _deps();
    await deps.modelManager.downloadModel(ModelCatalog.byId(kA)!);
    final svc = deps.voiceprintService;

    await deps.settings.setVoiceprintModelId(kA);
    await svc.enroll(name: '张三', note: '', samples: [Float32List(160)]);

    await svc.bindClone('张三', 'clone-1');
    expect(svc.profileOf('张三')?.cloneId, 'clone-1');

    // 重录同名不应丢掉绑定。
    await svc.enroll(name: '张三', note: '重录', samples: [Float32List(160)]);
    expect(svc.profileOf('张三')?.cloneId, 'clone-1');
    expect(svc.profileOf('张三')?.note, '重录');

    await svc.bindClone('张三', null);
    expect(svc.profileOf('张三')?.cloneId, isNull);
  });
}
