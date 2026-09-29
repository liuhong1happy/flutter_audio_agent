/// 知识库端到端测试(v1.0.2 新内容)。
///
/// 一条链路走到底:
///   设置 → 知识库子页 → **真实的多文件 raw 下载链路**(4 个文件、逐个体积校验)
///   → 知识库管理页 → 导入文本 → 后台索引 → 检索试跑命中 → 删除文档。
///
/// 断言尽量落在**用户能看到的东西**上(索引进度、相似度、片段正文、空态文案);
/// 只有"后台任务是否已落定"这类界面上看不见的时刻,才回落到服务/管理器状态
/// (见 [waitForCondition] 的注释)。
///
/// 运行方式(需已连接 Android 设备/模拟器;界面文案按英文断言,与既有 patrol
/// 测试一致 —— 设备语言为 en):
///   sh scripts/patrol_e2e.sh knowledge           # 推荐:跑完自动拉截图
///   patrol test -t patrol_test/knowledge_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts_demo/app.dart';
import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:patrol/patrol.dart';

import 'screenshot_helper.dart';
import 'test_deps.dart';

/// 导入的知识库文本与检索问句。
///
/// 这一对刻意选得"字符重叠高":假嵌入引擎按字符袋打分,实测余弦 **0.909**,
/// 高于默认阈值 0.45(量出来的,不是猜的)。换成无关句子只有 0.735 但混不进
/// top-k 的语义,故只用一条文档即可断言"检索到的是它"。
const String kKbTitle = '产品手册';
const String kKbText = '语音对话系统由离线识别与离线合成两部分组成。';
const String kKbQuery = '语音对话系统由哪两部分组成';

void main() {
  patrolTest('知识库:下载嵌入模型 → 导入 → 后台索引 → 检索试跑命中 → 删除', ($) async {
    final deps = await buildPatrolTestDeps();

    await $.pumpWidgetAndSettle(
      RepaintBoundary(
        key: screenshotBoundaryKey,
        child: TtsDemoApp(dependencies: deps),
      ),
    );

    // ── 设置 → 知识库子页 ───────────────────────────────────────────
    await $(#tabSettings).tap();
    await $.pumpAndSettle();
    await $(RegExp('Knowledge base')).tap();
    await $.pumpAndSettle();
    await takeScreenshot($.tester, '01_kb_section');

    // 还没下嵌入模型:此时既不该认为可检索,管理页也应按"未下载"处理。
    expect(deps.knowledgeService!.isModelReady, isFalse,
        reason: '测试开始时不该已经有嵌入模型');

    // 开关与两个滑块:纯设置项,点一下确认可用并写回。
    await $(#kbEnabledSwitch).tap();
    expect(deps.settings.kbEnabled, isFalse);
    await $(#kbEnabledSwitch).tap();
    expect(deps.settings.kbEnabled, isTrue);

    // ── 下载嵌入模型(多文件 raw:onnx + tokenizer + vocab + config)──
    // 假下载器按目录声明的**精确体积**落盘 —— 真实链路会逐文件比对体积,
    // 差一个字节就判"不完整",所以这条链路本身也在这里被端到端跑了一遍。
    await $(RegExp('Download')).tap();
    await $(Icons.check_circle)
        .waitUntilVisible(timeout: const Duration(seconds: 60));
    expect(deps.modelManager.isDownloaded(kDefaultEmbeddingModelId), isTrue);
    expect(deps.knowledgeService!.isModelReady, isTrue);
    await takeScreenshot($.tester, '02_embedding_model_ready');

    // ── 管理页:导入 ────────────────────────────────────────────────
    await $(#kbManageEntry).tap();
    await $.pumpAndSettle();
    // 模型已就绪 ⇒ 不该再出现"未下载"横幅(那会把用户吓退)。
    expect(find.textContaining('No embedding model'), findsNothing);

    await $(#kbImportButton).tap();
    await $.pumpAndSettle();
    await $(#kbImportTitleField).enterText(kKbTitle);
    await $(#kbImportContentField).enterText(kKbText);
    await $(#kbImportConfirm).tap();
    await $.pumpAndSettle();

    await $(RegExp('Imported')).waitUntilVisible(timeout: const Duration(seconds: 10));
    expect(find.text(kKbTitle), findsOneWidget,
        reason: '文档应立刻出现在列表里(不等索引)');
    await takeScreenshot($.tester, '03_kb_imported');

    // ── 后台索引跑完:列表从"索引中 x/y"变成"已索引 N" ────────────────
    await $(RegExp('indexing in the background')).waitUntilVisible(
      timeout: const Duration(seconds: 10),
    );
    await $(RegExp('indexed'))
        .waitUntilVisible(timeout: const Duration(seconds: 30));
    expect(deps.knowledgeService!.pendingChunks, 0,
        reason: '回填应已把待索引块清零');
    await takeScreenshot($.tester, '04_kb_indexed');

    // ── 检索试跑:命中并给出分数 ────────────────────────────────────
    await $(#kbProbeField).enterText(kKbQuery);
    await $(#kbProbeButton).tap();
    await $.pumpAndSettle();

    await $(RegExp('Similarity'))
        .waitUntilVisible(timeout: const Duration(seconds: 10));
    expect(find.textContaining('Nothing relevant found'), findsNothing);
    // 召回的是**片段正文**,不是标题 —— 这才说明向量确实参与了检索。
    expect(find.textContaining('离线识别'), findsWidgets);
    await takeScreenshot($.tester, '05_kb_probe_hit');

    // ── 删除文档:连带删块,回到空态 ────────────────────────────────
    await $(Icons.delete_outline).tap();
    await $(RegExp('removed too')).waitUntilVisible(timeout: const Duration(seconds: 10));
    await $(RegExp('OK')).tap();
    await $.pumpAndSettle();

    await $(RegExp('Knowledge base is empty'))
        .waitUntilVisible(timeout: const Duration(seconds: 10));
    expect(deps.knowledgeService!.documents, isEmpty);
    await takeScreenshot($.tester, '06_kb_empty_after_delete');

    await deps.streamingService.disposeAll();
  });
}
