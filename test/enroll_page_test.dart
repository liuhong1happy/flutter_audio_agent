/// 录制页冒烟:声纹模型下拉可见、切换会写回设置(记住上次选择),
/// 以及键盘弹出时不溢出(页面含 Spacer,插控件后最容易炸在这里)。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tts_demo/data/app_dependencies.dart';
import 'package:flutter_tts_demo/data/archive_extractor.dart';
import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';
import 'package:flutter_tts_demo/pages/voiceprint/sections/enroll_page.dart';
import 'package:flutter_tts_demo/utils/text_chunker.dart';

import 'support/fakes.dart';

const String kA = kLegacyVoiceprintModelId;
const String kB = '3dspeaker_speech_campplus_sv_zh-cn_16k-common';

/// 构造依赖并 init。真实文件 I/O 必须在 [WidgetTester.runAsync] 内进行,
/// 否则 Future 永远不会完成(测试直接挂到超时)。
Future<AppDependencies> _deps(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final tempDir = Directory.systemTemp.createTempSync('enroll_');
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
  await tester.runAsync(() async => deps.init());
  addTearDown(() async {
    await tester.runAsync(() async {
      deps.conversationService.dispose();
      await deps.streamingService.disposeAll();
    });
    tempDir.deleteSync(recursive: true);
  });
  return deps;
}

Future<void> _pump(WidgetTester tester, AppDependencies deps) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<AppDependencies>.value(value: deps),
        ChangeNotifierProvider.value(value: deps.settings),
        ChangeNotifierProvider.value(value: deps.modelManager),
        ChangeNotifierProvider.value(value: deps.voiceprintService),
        ChangeNotifierProvider.value(value: deps.voiceCloningService),
      ],
      child: MaterialApp(
        // 锁中文:断言的文案是中文的。
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const EnrollSpeakerPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('没有已下载的声纹模型:显示提示,不出下拉', (tester) async {
    final deps = await _deps(tester);
    await _pump(tester, deps);

    expect(
      find.byKey(const ValueKey('enrollVoiceprintModelSelector')),
      findsNothing,
    );
    expect(find.text('尚未下载任何模型'), findsOneWidget);
  });

  testWidgets('两个模型已下载:下拉初值 = 记住的上次选择,切换写回设置', (tester) async {
    final deps = await _deps(tester);
    await tester.runAsync(() async {
      await deps.modelManager.downloadModel(ModelCatalog.byId(kA)!);
      await deps.modelManager.downloadModel(ModelCatalog.byId(kB)!);
      await deps.settings.setVoiceprintModelId(kB);
    });

    await _pump(tester, deps);

    // 初值就是上次选的 B。
    final field = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey('enrollVoiceprintModelSelector')),
    );
    expect(field.initialValue, kB);

    // 切到 A → 设置被写回(这就是"记住上次选择")。
    await tester.tap(find.byKey(const ValueKey('enrollVoiceprintModelSelector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ModelCatalog.byId(kA)!.displayName).last);
    await tester.pumpAndSettle();

    expect(deps.settings.voiceprintModelId, kA);
  });

  testWidgets('键盘弹出时页面不溢出(可滚动)', (tester) async {
    final deps = await _deps(tester);
    await tester.runAsync(() async {
      await deps.modelManager.downloadModel(ModelCatalog.byId(kA)!);
      await deps.modelManager.downloadModel(ModelCatalog.byId(kB)!);
    });

    await tester.binding.setSurfaceSize(const Size(400, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // 模拟软键盘占掉大半屏。
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetViewInsets);

    await _pump(tester, deps);

    // 溢出会以异常形式抛在这里。
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('saveSpeakerButton')), findsOneWidget);
  });
}
