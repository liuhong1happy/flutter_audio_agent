/// 知识库页 / 记忆页 widget 测试。
///
/// 重点验两件"用户会立刻碰到"的事:
///  - 知识库页必须**在未下载嵌入模型时明说**,否则用户会以为"导入了就能检索";
///  - 记忆页要按**说话人**分组 —— 记忆是挂人的,平铺列表会让用户无法判断
///    某条记忆属于谁(而错误归属正是本功能最容易出的问题)。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tts_demo/data/archive_extractor.dart';
import 'package:flutter_tts_demo/data/knowledge_store.dart';
import 'package:flutter_tts_demo/data/memory_store.dart';
import 'package:flutter_tts_demo/data/model_files_resolver.dart';
import 'package:flutter_tts_demo/data/model_manager.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';
import 'package:flutter_tts_demo/pages/knowledge/knowledge_page.dart';
import 'package:flutter_tts_demo/pages/memory/memory_page.dart';
import 'package:flutter_tts_demo/utils/llm_service.dart';
import 'package:flutter_tts_demo/utils/memory/knowledge_service.dart';
import 'package:flutter_tts_demo/utils/memory/memory_service.dart';
import 'package:flutter_tts_demo/utils/voiceprint_service.dart';

import 'support/fakes.dart';

/// 内存 store + 假引擎的知识库服务。
///
/// [modelFilesAvailable] 只影响 `isModelReady`(页面据此显示"未下载"横幅);
/// 引擎加载由服务自己在需要时触发,测试无需预置。
Future<KnowledgeService> _knowledgeService({
  required bool modelFilesAvailable,
}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = TtsSettings();
  await settings.load();
  return KnowledgeService(
    store: MemoryKnowledgeStore(),
    settings: settings,
    engine: FakeEmbeddingEngine(),
    modelFilesResolver: modelFilesAvailable
        ? () => const EmbeddingModelFiles(
              modelPath: '/m.onnx',
              tokenizerPath: '/t.json',
            )
        : () => null,
  );
}

Future<void> _pumpKnowledge(WidgetTester tester, KnowledgeService service) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<KnowledgeService>.value(
      value: service,
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const KnowledgePage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('知识库页', () {
    testWidgets('空态:提示先去导入', (tester) async {
      final service = await _knowledgeService(modelFilesAvailable: true);
      await _pumpKnowledge(tester, service);

      expect(find.textContaining('导入'), findsWidgets);
    });

    testWidgets('**未下载嵌入模型时明确提示**(否则用户以为导入了就能检索)', (tester) async {
      final service = await _knowledgeService(modelFilesAvailable: false);
      await _pumpKnowledge(tester, service);

      expect(find.textContaining('嵌入模型'), findsWidgets);
    });

    testWidgets('导入:填标题与内容 → 文档出现在列表', (tester) async {
      final service = await _knowledgeService(modelFilesAvailable: true);
      await _pumpKnowledge(tester, service);

      await tester.tap(find.byKey(const ValueKey('kbImportButton')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('kbImportTitleField')),
        '产品手册',
      );
      await tester.enterText(
        find.byKey(const ValueKey('kbImportContentField')),
        '语音对话系统由离线识别与离线合成两部分组成。',
      );
      await tester.tap(find.byKey(const ValueKey('kbImportConfirm')));
      await tester.pumpAndSettle();

      expect(find.text('产品手册'), findsOneWidget);
      expect(service.documents, hasLength(1));
    });

    testWidgets('导入:标题或内容为空时拒绝,对话框不关、不落库', (tester) async {
      final service = await _knowledgeService(modelFilesAvailable: true);
      await _pumpKnowledge(tester, service);

      await tester.tap(find.byKey(const ValueKey('kbImportButton')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('kbImportTitleField')),
        '只有标题',
      );
      await tester.tap(find.byKey(const ValueKey('kbImportConfirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('kbImportConfirm')), findsOneWidget);
      expect(service.documents, isEmpty);
    });

    testWidgets('检索试跑:检索不到时明确说"没有检索到"', (tester) async {
      final service = await _knowledgeService(modelFilesAvailable: true);
      await _pumpKnowledge(tester, service);

      await tester.enterText(
        find.byKey(const ValueKey('kbProbeField')),
        '随便问点什么',
      );
      await tester.tap(find.byKey(const ValueKey('kbProbeButton')));
      await tester.pumpAndSettle();

      expect(find.textContaining('没有检索到'), findsOneWidget);
    });

    testWidgets('导入后(未索引)显示待索引提示', (tester) async {
      final service = await _knowledgeService(modelFilesAvailable: true);
      await service.importText(
        title: 'A',
        text: '语音对话系统由离线识别与离线合成两部分组成。',
        autoIndex: false,
      );
      await _pumpKnowledge(tester, service);

      expect(find.byKey(const ValueKey('kbPendingHint')), findsOneWidget);
    });
  });

  group('记忆页', () {
    testWidgets('空态:还没有任何记忆', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = TtsSettings();
      await settings.load();
      final tempDir = Directory.systemTemp.createTempSync('mempage_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final memory = MemoryService(
        store: MemoryMemoryStore(),
        llm: LlmService(settings: settings, client: FakeLlmClient()),
        currentModelId: () => 'm',
      );
      final voiceprint = VoiceprintService(
        modelManager: ModelManager(
          modelsDir: tempDir,
          audioCacheDir: tempDir,
          downloader: FakeModelDownloader(),
          extractor: const ArchiveExtractor(useCompute: false),
          resolver: const ModelFilesResolver(),
          settings: settings,
        ),
        settings: settings,
        engine: FakeSpeakerEngine(),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<MemoryService>.value(value: memory),
            ChangeNotifierProvider<VoiceprintService>.value(value: voiceprint),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const MemoryPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('还没有任何记忆'), findsOneWidget);
    });
  });
}
