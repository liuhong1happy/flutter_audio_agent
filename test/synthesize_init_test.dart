/// 合成页初始化卡片:没模型时给可点击的入口,下载后自动启用。
///
/// ⚠️ 该卡片与对话页初始化卡片**共用同一个 widget 树**(`IndexedStack` 会同时
/// 构建三个 Tab),所以它的按钮 key 必须与对话页的 `initDownloadButton` 区分开。
/// 这个文件里有一条断言就是钉住这一点的。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tts_demo/app.dart';
import 'package:flutter_tts_demo/data/app_dependencies.dart';
import 'package:flutter_tts_demo/data/archive_extractor.dart';
import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/utils/text_chunker.dart';

import 'support/fakes.dart';

Future<(AppDependencies, Directory)> _deps() async {
  SharedPreferences.setMockInitialValues({});
  final tempDir = Directory.systemTemp.createTempSync('synth_init_');
  final deps = AppDependencies(
    appLock: FakeAppLockService(),
    engine: FakeTtsEngine(segmentDuration: Duration.zero),
    downloader: FakeModelDownloader(),
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
    deps.conversationService.dispose();
    tempDir.deleteSync(recursive: true);
  });
  return (deps, tempDir);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('没有模型:显示初始化卡片(下载入口),没有输入框', (tester) async {
    final (deps, _) = await _deps();

    await tester.pumpWidget(TtsDemoApp(dependencies: deps));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('synthInitDownloadButton')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('ttsInput')), findsNothing);
    // 推荐的是最小体积的默认模型。
    expect(
      find.text(ModelCatalog.byId(kDefaultSynthModelId)!.displayName),
      findsOneWidget,
    );

    // 卡片按钮**不能**与对话页初始化卡片重名:两者同时存在于 widget 树里
    // (IndexedStack 会构建全部 Tab),重名会互相干扰对方的断言。
    expect(
      find.byKey(const ValueKey('initDownloadButton')),
      findsNothing,
      reason: '合成页不能用对话页的 initDownloadButton 做 key',
    );
  });

  testWidgets('点"下载并启用":模型就绪、卡片消失、出现输入框', (tester) async {
    final (deps, _) = await _deps();

    await tester.pumpWidget(TtsDemoApp(dependencies: deps));
    await tester.pumpAndSettle();

    // 真实文件 I/O 必须在 runAsync 内。
    await tester.runAsync(() async {
      await deps.modelManager
          .downloadModel(ModelCatalog.byId(kDefaultSynthModelId)!);
      await deps.settings.selectModel(kDefaultSynthModelId);
    });
    await tester.pumpAndSettle();

    expect(deps.settings.selectedModelId, kDefaultSynthModelId);
    expect(find.byKey(const ValueKey('synthInitDownloadButton')), findsNothing);
    expect(find.byKey(const ValueKey('ttsInput')), findsOneWidget);
  });

  testWidgets('选了但没下载:文案走"所选模型尚未下载"', (tester) async {
    final (deps, _) = await _deps();
    // 选中一个没下载的模型(不是默认那个,以区分两种子情况)。
    const other = 'vits-zh-hf-theresa';
    await deps.settings.selectModel(other);

    await tester.pumpWidget(TtsDemoApp(dependencies: deps));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('synthInitDownloadButton')), findsOneWidget);
    expect(find.text(ModelCatalog.byId(other)!.displayName), findsOneWidget);
  });
}
