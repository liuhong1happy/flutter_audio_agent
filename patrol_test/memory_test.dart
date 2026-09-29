/// 长期记忆端到端测试(v1.0.2 新内容)。
///
/// 覆盖"从对话里长出记忆"的整条链路:
///   已注册说话人开口 → 回复 → **轮末异步抽取**(LLM 返回 ADD) → 落库
///   → 记忆管理页按说话人分组显示 → 单条删除 → 清空该说话人。
///
/// 为什么要跑真机/模拟器而不是 widget 测试:抽取是**轮末 fire-and-forget** 触发的
/// (不阻塞对话),而"它到底有没有落库、落到了谁名下"正是这条链路最容易出错的地方。
///
/// 运行方式(需已连接 Android 设备/模拟器):
///   sh scripts/patrol_e2e.sh memory           # 推荐:跑完自动拉截图
///   patrol test -t patrol_test/memory_test.dart
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts_demo/app.dart';
import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:patrol/patrol.dart';

import '../test/support/fakes.dart';
import 'screenshot_helper.dart';
import 'test_deps.dart';
import 'wait_helper.dart';

/// 抽取器应当吐出的那条记忆(与页面上要断言的内容一致)。
const String kFact = '偏好简洁回答';

const String kExtractJson =
    '[{"op":"ADD","kind":"preference","content":"$kFact","confidence":0.9}]';

void main() {
  patrolTest('长期记忆:对话中提炼入库 → 按说话人分组 → 单条删除 → 清空', ($) async {
    // 抽取间隔调成 1 轮:默认 4 轮会让这个测试为了"攒够轮数"白跑三轮。
    // ⚠️ 必须在 init **之前**设置 —— MemoryService 是 init 时把间隔读进去的。
    final settings = TtsSettings();
    await settings.load();
    await settings.setMemoryExtractInterval(1);

    final speakerEngine = FakeSpeakerEngine()..nextName = '张三';
    final vad = FakeVadEngine();
    final asr = FakeAsrEngine()..nextText = '我平时喜欢简洁一点的回答';
    final llm = FakeLlmClient();
    // 同一个 LLM 客户端既生成回复、又做记忆抽取,按系统提示分流
    // (抽取器的系统提示以"你是记忆抽取器"开头)。
    llm.responder = (messages) => messages.first.content.contains('记忆抽取')
        ? [kExtractJson]
        : ['好的,记住了'];

    final deps = await buildPatrolTestDeps(
      settings: settings,
      llmClient: llm,
      vadEngine: vad,
      asrEngine: asr,
      speakerEngine: speakerEngine,
    );

    // 对话需要的模型(ASR/VAD/TTS)+ 声纹模型,并注册一位说话人 ——
    // 未知说话人是**不抽取**的(跨人隔离硬约束),所以必须先"有人"。
    await deps.conversationService.downloadInitialModels(null);
    await deps.modelManager
        .downloadModel(ModelCatalog.byId(kLegacyVoiceprintModelId)!);
    await deps.voiceprintService.enroll(
      name: '张三',
      note: '同事',
      samples: [Float32List(16000)],
    );
    await deps.settings.setLlmApiKey('k');

    await $.pumpWidgetAndSettle(
      RepaintBoundary(
        key: screenshotBoundaryKey,
        child: TtsDemoApp(dependencies: deps),
      ),
    );

    // ── 说一句"值得记"的话(音频模式才会走声纹识别,拿到说话人)──────
    await $(#tabConversation).tap();
    await $.pumpAndSettle();
    await $(#conversationToggleButton).tap();
    await $.pumpAndSettle();
    vad.emitSegment(Float32List(1600));
    await $(RegExp('好的,记住了'))
        .waitUntilVisible(timeout: const Duration(seconds: 20));
    await takeScreenshot($.tester, '01_reply_after_turn');

    // 抽取在轮末异步跑,界面上没有信号 —— 只能等它落库。
    await waitForCondition(
      $,
      what: '轮末记忆抽取落库到"张三"名下',
      ready: () async => (await deps.memoryService!.listFor('张三')).isNotEmpty,
    );
    final extracted = await deps.memoryService!.listFor('张三');
    expect(extracted.single.content, kFact);
    expect(extracted.single.speaker, '张三');

    // ── 记忆管理页:按说话人分组 ────────────────────────────────────
    await $(#tabSettings).tap();
    await $.pumpAndSettle();
    await $(RegExp('Memory')).tap();
    await $.pumpAndSettle();
    await takeScreenshot($.tester, '02_memory_section');

    await $(#memoryManageEntry).tap();
    await $.pumpAndSettle();

    // 分组标题必须带说话人名与条数 —— 平铺列表会让人看不出这条记忆属于谁。
    await $(RegExp('张三 · 1'))
        .waitUntilVisible(timeout: const Duration(seconds: 10));
    expect(find.textContaining(kFact), findsWidgets);
    await takeScreenshot($.tester, '03_memory_grouped_by_speaker');

    // ── 单条删除 ────────────────────────────────────────────────────
    await $(Icons.close).tap();
    await $(RegExp('No memories yet'))
        .waitUntilVisible(timeout: const Duration(seconds: 10));
    expect(await deps.memoryService!.listFor('张三'), isEmpty);

    // ── 清空该说话人(先补两条手动记忆,跳过 LLM)────────────────────
    await deps.memoryService!.remember(
      speaker: '张三',
      content: '在做 Flutter 语音项目',
    );
    await deps.memoryService!.remember(speaker: '张三', content: '住在杭州');
    // 页面在 initState 里读一次列表,所以要重新进一次页面。
    await $.tester.pageBack();
    await $.pumpAndSettle();
    await $(#memoryManageEntry).tap();
    await $.pumpAndSettle();
    await $(RegExp('张三 · 2'))
        .waitUntilVisible(timeout: const Duration(seconds: 10));
    await takeScreenshot($.tester, '04_memory_two_items');

    // 说话人名是中文,`#张三` 这种 Symbol 写法非法,用 ValueKey 定位。
    await $(const ValueKey('memoryClear_张三')).tap();
    await $(RegExp('cannot be undone'))
        .waitUntilVisible(timeout: const Duration(seconds: 10));
    await $(RegExp('OK')).tap();
    await $.pumpAndSettle();

    await $(RegExp('No memories yet'))
        .waitUntilVisible(timeout: const Duration(seconds: 10));
    expect(await deps.memoryService!.listFor('张三'), isEmpty);
    await takeScreenshot($.tester, '05_memory_cleared');

    deps.conversationService.dispose();
    await deps.streamingService.disposeAll();
  });
}
