/// 模型下载多镜像回退逻辑测试。
///
/// 验证:候选顺序(手动镜像 → 代理 → 直连)、失败自动切换、
/// bzip2 魔数校验拒收代理错误页并回退。
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tts_demo/data/app_dependencies.dart';
import 'package:flutter_tts_demo/data/archive_extractor.dart';
import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/data/model_downloader.dart';
import 'package:flutter_tts_demo/data/model_manager.dart';
import 'package:flutter_tts_demo/utils/text_chunker.dart';

import 'support/fakes.dart';

enum _Result { ok, fail, badBzip, partial }

/// 可编排结果的下载器:按 URL 决定成功/失败/返回非 bzip2 错误页。
class _ScriptedDownloader implements ModelDownloader {
  _ScriptedDownloader([Map<String, _Result>? script])
      : script = script ?? <String, _Result>{};

  final Map<String, _Result> script;

  /// 按调用顺序记录被请求的 URL。
  final List<String> calls = [];

  @override
  Future<void> download({
    required String url,
    required String savePath,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    calls.add(url);
    final result = script[url] ?? _Result.fail;
    onProgress?.call(0, 100);
    switch (result) {
      case _Result.fail:
        throw DioException(requestOptions: RequestOptions(path: url));
      case _Result.badBzip:
        // 模拟代理返回的 HTML 错误页。
        final f = File(savePath);
        await f.parent.create(recursive: true);
        await f.writeAsString('<!DOCTYPE html><html>proxy error</html>');
        onProgress?.call(100, 100);
      case _Result.partial:
        // 下载一部分后断网(用于验证部分文件被保留,支持续传)。
        final f = File(savePath);
        await f.parent.create(recursive: true);
        await f.writeAsBytes(List<int>.filled(100, 7));
        onProgress?.call(50, 100);
        throw DioException(requestOptions: RequestOptions(path: url));
      case _Result.ok:
        final f = File(savePath);
        await f.parent.create(recursive: true);
        await f.writeAsBytes(buildFakeModelArchive());
        onProgress?.call(100, 100);
    }
  }
}

Future<({ModelManager manager, _ScriptedDownloader downloader})> _setup({
  required _ScriptedDownloader downloader,
}) async {
  SharedPreferences.setMockInitialValues({});
  final tempDir = Directory.systemTemp.createTempSync('model_mgr_');
  final deps = AppDependencies(
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
  addTearDown(() async {
    await deps.streamingService.disposeAll();
    tempDir.deleteSync(recursive: true);
  });
  return (manager: deps.modelManager, downloader: downloader);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('downloadCandidates 顺序:手动镜像 → 国内代理 → 直连', () async {
    final dl = _ScriptedDownloader();
    final deps = await _setup(downloader: dl);
    await deps.manager.settings.setMirrorPrefix('https://my-mirror.example/');

    final model = ModelCatalog.all.first;
    final candidates = deps.manager.downloadCandidates(model);
    expect(candidates.first, 'https://my-mirror.example/${model.url}',
        reason: '手动镜像应排第一');
    expect(candidates.last, model.url, reason: '直连应兜底最后');
    expect(candidates.length, greaterThan(2));
  });

  test('首个源失败自动切换到下一个镜像', () async {
    final model = ModelCatalog.all.first;
    // 预置手动镜像,让候选顺序确定。
    final dl = _ScriptedDownloader();
    final deps = await _setup(downloader: dl);
    await deps.manager.settings.setMirrorPrefix('https://my-mirror.example/');
    final candidates = deps.manager.downloadCandidates(model);
    dl.script[candidates[0]] = _Result.fail;
    dl.script[candidates[1]] = _Result.ok;

    await deps.manager.downloadModel(model);

    expect(deps.manager.isDownloaded(model.id), isTrue,
        reason: '应回退到第二个源并下载成功');
    expect(dl.calls, [candidates[0], candidates[1]],
        reason: '应按顺序尝试:失败源 → 成功源');
  });

  test('bzip2 魔数校验拒收代理错误页并回退', () async {
    final model = ModelCatalog.all.first;
    final dl = _ScriptedDownloader();
    final deps = await _setup(downloader: dl);
    await deps.manager.settings.setMirrorPrefix('https://my-mirror.example/');
    final candidates = deps.manager.downloadCandidates(model);
    dl.script[candidates[0]] = _Result.badBzip;
    dl.script[candidates[1]] = _Result.ok;

    await deps.manager.downloadModel(model);

    expect(deps.manager.isDownloaded(model.id), isTrue,
        reason: '错误页应被魔数校验拒收并回退');
    expect(dl.calls, [candidates[0], candidates[1]]);
  });

  test('所有源均失败时进入 error 状态', () async {
    final model = ModelCatalog.all.first;
    final dl = _ScriptedDownloader();
    final deps = await _setup(downloader: dl);
    await deps.manager.settings.setMirrorPrefix('https://my-mirror.example/');
    final candidates = deps.manager.downloadCandidates(model);
    dl.script[candidates[0]] = _Result.fail; // 其余默认 fail。

    await deps.manager.downloadModel(model);

    expect(deps.manager.isDownloaded(model.id), isFalse);
    expect(deps.manager.stateOf(model).status, DownloadStatus.error,
        reason: '全部源失败应进入 error 状态');
  });

  test('网络失败保留部分文件,支持下次断点续传', () async {
    final model = ModelCatalog.all.first;
    final dl = _ScriptedDownloader();
    final deps = await _setup(downloader: dl);
    await deps.manager.settings.setMirrorPrefix('https://my-mirror.example/');
    final candidates = deps.manager.downloadCandidates(model);
    dl.script[candidates[0]] = _Result.partial; // 写了 100 字节后断网。
    dl.script[candidates[1]] = _Result.fail; // 下一个源也失败。

    await deps.manager.downloadModel(model);

    expect(deps.manager.isDownloaded(model.id), isFalse);
    expect(deps.manager.stateOf(model).status, DownloadStatus.error);
    // 关键:网络失败后部分文件不应被删除(供下次 Range 续传)。
    final partial = File(deps.manager.modelArchivePath(model));
    expect(await partial.exists(), isTrue, reason: '网络失败应保留部分文件');
    expect(await partial.length(), 100, reason: '应保留已下载的 100 字节');
  });
}
