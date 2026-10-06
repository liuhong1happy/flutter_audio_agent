/// 模型目录泛化测试:resolver 各 kind 解析 + rawFile 下载分支。
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tts_demo/data/app_dependencies.dart';
import 'package:flutter_tts_demo/data/archive_extractor.dart';
import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/data/model_downloader.dart';
import 'package:flutter_tts_demo/data/model_files_resolver.dart';
import 'package:flutter_tts_demo/data/model_manager.dart';
import 'package:flutter_tts_demo/utils/text_chunker.dart';

import 'support/fakes.dart';

void main() {
  const resolver = ModelFilesResolver();

  Directory makeDir() => Directory.systemTemp.createTempSync('resolver_');

  test('TTS(vits)解析 model+tokens+lexicon+ruleFsts', () {
    final d = makeDir();
    addTearDown(() => d.deleteSync(recursive: true));
    File('${d.path}/model.onnx').writeAsBytesSync(List.filled(100, 1));
    File('${d.path}/tokens.txt').writeAsStringSync('');
    File('${d.path}/lexicon.txt').writeAsStringSync('');
    File('${d.path}/number.fst').writeAsStringSync('');

    final model = ModelCatalog.byId('vits-piper-zh_CN-xiao_ya-medium-int8')!;
    final r = resolver.resolve(model, d.path)!;
    expect(r.isComplete, isTrue);
    expect(r.modelPath, endsWith('model.onnx'));
    expect(r.tokensPath, endsWith('tokens.txt'));
    expect(r.lexiconPath, endsWith('lexicon.txt'));
    expect(r.ruleFsts, isNotEmpty);
  });

  // 新增的两个 Piper 中文模型**结构不同**,各按真实解包结果固化一条:
  // 目录里文件按实测命名写(见 lib/data/model_catalog.dart 里对应的注释)。

  test('TTS piper chaowen:与晓雅同结构(lexicon + phone/date/number.fst)', () {
    final d = makeDir();
    addTearDown(() => d.deleteSync(recursive: true));
    File('${d.path}/zh_CN-chaowen-medium.onnx')
        .writeAsBytesSync(List.filled(100, 1));
    File('${d.path}/tokens.txt').writeAsStringSync('');
    File('${d.path}/lexicon.txt').writeAsStringSync('');
    File('${d.path}/phone.fst').writeAsStringSync('');
    File('${d.path}/date.fst').writeAsStringSync('');
    File('${d.path}/number.fst').writeAsStringSync('');

    final model = ModelCatalog.byId('vits-piper-zh_CN-chaowen-medium-int8')!;
    final r = resolver.resolve(model, d.path)!;
    expect(r.isComplete, isTrue);
    expect(r.modelPath, endsWith('zh_CN-chaowen-medium.onnx'));
    expect(r.tokensPath, endsWith('tokens.txt'));
    expect(r.lexiconPath, endsWith('lexicon.txt'));
    // 声明的三个 fst **全部**能在包里找到(否则张量归一化会静默少一环)。
    expect(r.ruleFsts, hasLength(3));
  });

  test('TTS piper huayan:走 espeak-ng-data 分支,**没有 fst/lexicon**', () {
    final d = makeDir();
    addTearDown(() => d.deleteSync(recursive: true));
    File('${d.path}/zh_CN-huayan-medium.onnx')
        .writeAsBytesSync(List.filled(100, 1));
    File('${d.path}/tokens.txt').writeAsStringSync('');
    // 真实包内是 espeak-ng-data/ 一整个目录(392 个文件)。
    Directory('${d.path}/espeak-ng-data').createSync();
    File('${d.path}/espeak-ng-data/phondata').writeAsStringSync('');

    final model = ModelCatalog.byId('vits-piper-zh_CN-huayan-medium')!;
    final r = resolver.resolve(model, d.path)!;
    // 齐不齐看 dataDir,不是看 lexicon —— 这条正是"照抄晓雅"会踩错的地方。
    expect(r.isComplete, isTrue);
    expect(r.lexiconPath, isNull);
    expect(r.dataDir, endsWith('espeak-ng-data'));
    expect(r.ruleFsts, isEmpty, reason: '包内没有任何 .fst,声明 ruleFsts 也找不到');
  });

  test('ASR(paraformer)解析 model+tokens', () {
    final d = makeDir();
    addTearDown(() => d.deleteSync(recursive: true));
    File('${d.path}/model.onnx').writeAsBytesSync(List.filled(100, 1));
    File('${d.path}/tokens.txt').writeAsStringSync('');

    final model = ModelCatalog.byId('sherpa-onnx-paraformer-zh-2023-09-14')!;
    final r = resolver.resolve(model, d.path)!;
    expect(r.isComplete, isTrue);
    expect(r.modelPath, endsWith('model.onnx'));
    expect(r.tokensPath, endsWith('tokens.txt'));
  });

  test('speaker 裸 onnx 按 rawFileName 解析', () {
    final d = makeDir();
    addTearDown(() => d.deleteSync(recursive: true));
    final model =
        ModelCatalog.byId('3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k')!;
    File('${d.path}/${model.rawFileName}').writeAsBytesSync(List.filled(100, 1));

    final r = resolver.resolve(model, d.path)!;
    expect(r.isComplete, isTrue);
    expect(r.modelPath, endsWith(model.rawFileName!));
  });

  test('CAMPPlus 声纹模型同样走裸 onnx 分支', () {
    final d = makeDir();
    addTearDown(() => d.deleteSync(recursive: true));
    final model =
        ModelCatalog.byId('3dspeaker_speech_campplus_sv_zh-cn_16k-common')!;
    File('${d.path}/${model.rawFileName}').writeAsBytesSync(List.filled(100, 1));

    final r = resolver.resolve(model, d.path)!;
    expect(r.isComplete, isTrue);
    expect(r.modelPath, endsWith(model.rawFileName!));

    // 两个声纹模型的文件名不同 —— 同一个目录里不会互相误匹配。
    expect(
      model.rawFileName,
      isNot(ModelCatalog.byId(kLegacyVoiceprintModelId)!.rawFileName),
    );
  });

  test('vad 裸 onnx 解析', () {
    final d = makeDir();
    addTearDown(() => d.deleteSync(recursive: true));
    final model = ModelCatalog.byId('silero_vad')!;
    File('${d.path}/${model.rawFileName}').writeAsBytesSync(List.filled(100, 1));

    final r = resolver.resolve(model, d.path)!;
    expect(r.isComplete, isTrue);
    expect(r.modelPath, endsWith('silero_vad.onnx'));
  });

  test('pocket 7 文件齐才 isComplete', () {
    final d = makeDir();
    addTearDown(() => d.deleteSync(recursive: true));
    final model = ModelCatalog.byId('sherpa-onnx-pocket-tts-int8-2026-01-26')!;
    for (final name in [
      'lm_flow.int8.onnx',
      'lm_main.int8.onnx',
      'encoder.onnx',
      'decoder.int8.onnx',
      'text_conditioner.onnx',
      'vocab.json',
      'token_scores.json',
    ]) {
      File('${d.path}/$name').writeAsBytesSync(List.filled(100, 1));
    }

    final r = resolver.resolve(model, d.path)!;
    expect(r.isComplete, isTrue);
    expect(r.pocket!.encoder, endsWith('encoder.onnx'));

    // 缺一个 json 即不完整。
    File('${d.path}/vocab.json').deleteSync();
    final r2 = resolver.resolve(model, d.path)!;
    expect(r2.isComplete, isFalse);
  });

  test('rawFile 下载跳过 bzip2 校验与解压,直接 ready', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final tempDir = Directory.systemTemp.createTempSync('raw_');
    final deps = AppDependencies(
      appLock: FakeAppLockService(),
      engine: FakeTtsEngine(segmentDuration: Duration.zero),
      downloader: _RawDownloader(),
      chunker: TextChunker(enableJieba: false),
      extractor: const ArchiveExtractor(useCompute: false),
      player: FakeAudioPlaybackQueue(),
      micRecorder: FakeMicRecorder(),
      conversationPlayer: FakeAudioPlaybackQueue(),
      conversationStore: MemoryConversationStore(),
      modelsDirProvider: () async => Directory('${tempDir.path}/models'),
      audioCacheDirProvider: () async => Directory('${tempDir.path}/audio'),
      cloneRefsDirProvider: () async => Directory('${tempDir.path}/clone_refs'),
    );
    await deps.init();
    addTearDown(() async {
      await deps.streamingService.disposeAll();
      tempDir.deleteSync(recursive: true);
    });

    final model = ModelCatalog.byId('silero_vad')!;
    await deps.modelManager.downloadModel(model);

    expect(deps.modelManager.isDownloaded(model.id), isTrue);
    expect(deps.modelManager.stateOf(model).status, DownloadStatus.ready);
    expect(await File(deps.modelManager.rawFilePath(model)).exists(), isTrue);
    expect(deps.modelManager.resolveModel(model)!.isComplete, isTrue);
  });
}

/// 写入非 bzip2 的裸字节,验证 rawFile 分支不跑魔数校验。
class _RawDownloader implements ModelDownloader {
  @override
  Future<void> download({
    required String url,
    required String savePath,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final f = File(savePath);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(List<int>.filled(4096, 7));
    onProgress?.call(4096, 4096);
  }
}
