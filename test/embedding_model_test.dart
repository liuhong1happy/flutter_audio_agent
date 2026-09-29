/// 文本嵌入模型(知识库/记忆检索)的目录、resolver 与多文件下载测试。
///
/// 这一组守的是"静默错误"高发区:
///  - 模型来自 **ModelScope** 而非 GitHub ⇒ 代理前缀**不能**套上去;
///  - 它是**多文件**下载 ⇒ 少一个文件、或某个文件其实是网关的 HTML 错误页,
///    都必须被抓住,而不是留到运行时才报一个难读的加载错误;
///  - `onnx-community` 那份**外置数据**拆分格式必须被拒绝。
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
import 'package:flutter_tts_demo/data/model_manager.dart' show DownloadStatus;
import 'package:flutter_tts_demo/data/models/tts_model.dart';
import 'package:flutter_tts_demo/utils/text_chunker.dart';

import 'support/fakes.dart';

/// 按 URL 末尾文件名写**精确字节数**的假下载器。
///
/// 多文件 raw 下载会逐个做精确体积校验,所以这里必须写对长度,
/// 否则测的就不是"下载成功"而是"体积校验生效"。
class _SizeAwareDownloader implements ModelDownloader {
  _SizeAwareDownloader(this.sizes, {this.corrupt = const {}});

  /// 文件名 → 应写字节数。
  final Map<String, int> sizes;

  /// 需要故意写错长度的文件名(用于验证校验会拦住)。
  final Set<String> corrupt;

  final List<String> urls = [];

  @override
  Future<void> download({
    required String url,
    required String savePath,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    urls.add(url);
    final name = url.split('/').last;
    final expected = sizes[name] ?? 8;
    final actual = corrupt.contains(name) ? expected + 1 : expected;
    final file = File(savePath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(List<int>.filled(actual, 7));
    onProgress?.call(actual, actual);
  }
}

/// 小体积的合成嵌入模型(避免在测试里真写 24MB)。
TtsModel _tinyEmbeddingModel({int onnxBytes = 2048, bool includeVocab = true}) {
  return TtsModel(
    id: 'tiny-embed',
    displayName: '合成嵌入模型',
    description: '测试用',
    url: 'https://modelscope.cn/models/Xenova/bge-small-zh-v1.5/resolve/master',
    tarBz2SizeBytes: 0,
    license: 'MIT',
    kind: ModelKind.embedding,
    downloadFormat: ModelDownloadFormat.rawFile,
    rawFiles: [
      ModelRawFile(
        remotePath: 'onnx/model_quantized.onnx',
        fileName: 'model_quantized.onnx',
        sizeBytes: onnxBytes,
      ),
      ModelRawFile(
        remotePath: 'tokenizer.json',
        fileName: 'tokenizer.json',
        sizeBytes: 32,
      ),
      if (includeVocab)
        ModelRawFile(
          remotePath: 'vocab.txt',
          fileName: 'vocab.txt',
          sizeBytes: 16,
        ),
      ModelRawFile(
        remotePath: 'config.json',
        fileName: 'config.json',
        sizeBytes: 8,
      ),
    ],
  );
}

void main() {
  group('目录:嵌入模型条目', () {
    test('真实条目存在且形状正确', () {
      final m = ModelCatalog.byId(kDefaultEmbeddingModelId);
      expect(m, isNotNull);
      expect(m!.kind, ModelKind.embedding);
      expect(m.downloadFormat, ModelDownloadFormat.rawFile);
      expect(m.rawFiles, isNotNull);
      expect(m.rawFiles!.length, 4, reason: 'onnx + tokenizer + vocab + config');

      // 体积与 ModelScope API 报的字节数一致(2026-09-29 实测)。
      final byName = {
        for (final f in m.rawFiles!) f.fileName: f.sizeBytes,
      };
      expect(byName['model_quantized.onnx'], 24010842);
      expect(byName['tokenizer.json'], 439125);
      expect(byName['vocab.txt'], 109540);
      expect(byName['config.json'], 716);
      expect(m.totalSizeBytes, 24010842 + 439125 + 109540 + 716);
    });

    test('byKind(embedding) 能取到,且不影响其他 kind 的默认项', () {
      expect(ModelCatalog.byKind(ModelKind.embedding)?.id,
          kDefaultEmbeddingModelId);
      // 声纹默认仍必须是老模型(老档案迁移依赖它)。
      expect(ModelCatalog.byKind(ModelKind.speaker)?.id,
          kLegacyVoiceprintModelId);
      // 嵌入模型不应混进 TTS 列表。
      expect(
        ModelCatalog.multiSpeaker().any((m) => m.kind == ModelKind.embedding),
        isFalse,
      );
    });

    test('多文件条目体积取和,sizeLabel 用总值', () {
      final m = _tinyEmbeddingModel();
      expect(m.totalSizeBytes, 2048 + 32 + 16 + 8);
      expect(m.sizeLabel, isNotEmpty);
    });
  });

  group('resolver:嵌入模型', () {
    Directory makeDir() => Directory.systemTemp.createTempSync('emb_res_');
    const resolver = ModelFilesResolver();

    test('onnx + tokenizer.json 齐 ⇒ 完整', () {
      final d = makeDir();
      addTearDown(() => d.deleteSync(recursive: true));
      File('${d.path}/model_quantized.onnx').writeAsBytesSync(List.filled(4096, 1));
      File('${d.path}/tokenizer.json').writeAsStringSync('{}');
      File('${d.path}/vocab.txt').writeAsStringSync('x');
      File('${d.path}/config.json').writeAsStringSync('{}');

      final r = resolver.resolve(_tinyEmbeddingModel(), d.path)!;
      expect(r.modelPath, endsWith('model_quantized.onnx'));
      expect(r.tokenizerJsonPath, endsWith('tokenizer.json'));
      expect(r.isComplete, isTrue);
    });

    test('缺 tokenizer.json ⇒ 不完整', () {
      final d = makeDir();
      addTearDown(() => d.deleteSync(recursive: true));
      File('${d.path}/model_quantized.onnx').writeAsBytesSync(List.filled(4096, 1));

      final r = resolver.resolve(_tinyEmbeddingModel(), d.path)!;
      expect(r.isComplete, isFalse);
    });

    test('**外置数据拆分格式被拒**:目录里出现 .onnx_data ⇒ 判为不完整', () {
      // 这是 `onnx-community/...-ONNX` 那份的形状:`.onnx` 只有 168KB 的图,
      // 权重在同名 `.onnx_data` 里。只下 `.onnx` 会加载失败且报错难读,
      // 所以这里主动判为不完整,把问题拦在下载阶段。
      final d = makeDir();
      addTearDown(() => d.deleteSync(recursive: true));
      File('${d.path}/model_quantized.onnx').writeAsBytesSync(List.filled(4096, 1));
      File('${d.path}/model_quantized.onnx_data').writeAsBytesSync(List.filled(4096, 1));
      File('${d.path}/tokenizer.json').writeAsStringSync('{}');

      final r = resolver.resolve(_tinyEmbeddingModel(), d.path)!;
      expect(r.isComplete, isFalse,
          reason: '外置数据格式必须被拒绝,不能带病通过');
    });
  });

  group('下载源候选:代理只对 GitHub 生效', () {
    late Directory tempDir;
    late AppDependencies deps;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      tempDir = Directory.systemTemp.createTempSync('emb_cand_');
      deps = AppDependencies(
        appLock: FakeAppLockService(),
        engine: FakeTtsEngine(segmentDuration: Duration.zero),
        downloader: _SizeAwareDownloader(const {}),
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
    });

    tearDown(() async {
      await deps.streamingService.disposeAll();
      tempDir.deleteSync(recursive: true);
    });

    test('ModelScope 地址不做代理回退(套 GitHub 代理必然失败)', () {
      final m = ModelCatalog.byId(kDefaultEmbeddingModelId)!;
      final candidates = deps.modelManager.downloadCandidates(m);
      expect(candidates.length, 1, reason: '非 GitHub 源只有一个候选');
      expect(candidates.single, m.url);
      expect(candidates.single, contains('modelscope.cn'));
    });

    test('GitHub 地址仍走多代理回退', () {
      final m = ModelCatalog.byId(kDefaultSynthModelId)!;
      final candidates = deps.modelManager.downloadCandidates(m);
      expect(candidates.length, greaterThan(1));
      expect(candidates.last, m.url); // 直连兜底在最后
    });
  });

  group('manager:多文件 raw 下载', () {
    late Directory tempDir;
    late AppDependencies deps;
    late _SizeAwareDownloader downloader;

    Future<void> setupWith(Map<String, int> sizes,
        {Set<String> corrupt = const {}}) async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      tempDir = Directory.systemTemp.createTempSync('emb_dl_');
      downloader = _SizeAwareDownloader(sizes, corrupt: corrupt);
      deps = AppDependencies(
        appLock: FakeAppLockService(),
        engine: FakeTtsEngine(segmentDuration: Duration.zero),
        downloader: downloader,
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
    }

    tearDown(() async {
      if (deps.modelManager.stateOf(_tinyEmbeddingModel()).isDownloading) {
        deps.modelManager.cancelDownload(_tinyEmbeddingModel());
      }
      await deps.streamingService.disposeAll();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('四个文件逐个下载 ⇒ ready,且每个 URL 都指向 ModelScope', () async {
      final model = _tinyEmbeddingModel();
      await setupWith({
        'model_quantized.onnx': 2048,
        'tokenizer.json': 32,
        'vocab.txt': 16,
        'config.json': 8,
      });

      await deps.modelManager.downloadModel(model);

      expect(deps.modelManager.stateOf(model).status, DownloadStatus.ready,
          reason: '错误信息: ${deps.modelManager.stateOf(model).error}');
      expect(deps.modelManager.isDownloaded(model.id), isTrue);
      expect(downloader.urls.length, 4);
      for (final u in downloader.urls) {
        expect(u, startsWith(model.url));
        expect(u, contains('modelscope.cn'));
      }
      // onnx 的远端路径带目录,落盘是扁平的 —— 断言这条扁平化约定。
      expect(downloader.urls.any((u) => u.endsWith('/onnx/model_quantized.onnx')),
          isTrue);
      expect(
        File('${deps.modelManager.modelUnpackedDir(model)}/model_quantized.onnx')
            .existsSync(),
        isTrue,
      );
      expect(deps.modelManager.resolveModel(model)!.isComplete, isTrue);
    });

    test('已下好的文件不重下(断点续)', () async {
      final model = _tinyEmbeddingModel();
      await setupWith({
        'model_quantized.onnx': 2048,
        'tokenizer.json': 32,
        'vocab.txt': 16,
        'config.json': 8,
      });
      await deps.modelManager.downloadModel(model);
      expect(downloader.urls.length, 4);

      // 第二次下载:四个文件都已存在且体积正确 ⇒ 不应再发任何请求。
      await deps.modelManager.downloadModel(model);
      expect(downloader.urls.length, 4, reason: '已完整的文件不该被重下');
    });

    test('**某一个文件体积不符 ⇒ 报错,不静默当成成功**', () async {
      // 模拟"下载源返回了 HTML 拦截页":状态码 200 但内容是别的东西。
      final model = _tinyEmbeddingModel();
      await setupWith(
        {
          'model_quantized.onnx': 2048,
          'tokenizer.json': 32,
          'vocab.txt': 16,
          'config.json': 8,
        },
        corrupt: {'tokenizer.json'},
      );

      await deps.modelManager.downloadModel(model);

      final state = deps.modelManager.stateOf(model);
      expect(state.status, DownloadStatus.error);
      expect(state.error, contains('tokenizer.json'));
      expect(state.error, contains('体积不符'));
      expect(deps.modelManager.isDownloaded(model.id), isFalse);
    });
  });
}
