/// 上下文编排端到端测试(v1.0.2 新内容,本版核心)。
///
/// 验证三块新内容最终都汇进了**真正发给大模型的那一份提示词**:
///   ③ 知识库片段(检索命中 + 来源标题)④ 该说话人的长期记忆 ⑤ 会话滚动摘要
/// 外加最要紧的一条隔离约束:**未注册说话人拿不到任何长期记忆**。
///
/// 断言落在 `FakeLlmClient.capturedMessages` 上 —— "注入到底有没有生效"在界面上
/// 看不出来、在日志里也看不出来,只有送出去的报文是可信证据。
/// (顺带守住语音场景的专属约束:提示词必须要求别念出 `[1]` 这类标记。)
///
/// 运行方式(需已连接 Android 设备/模拟器):
///   sh scripts/patrol_e2e.sh context_injection   # 推荐:跑完自动拉截图
///   patrol test -t patrol_test/context_injection_test.dart
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts_demo/app.dart';
import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/data/session_memory_store.dart';
import 'package:flutter_tts_demo/utils/conversation_service.dart';
import 'package:patrol/patrol.dart';

import '../test/support/fakes.dart';
import 'screenshot_helper.dart';
import 'test_deps.dart';
import 'wait_helper.dart';

/// 知识库文档与问句。
///
/// 这一对的"查询↔块"余弦实测 **0.909**(假嵌入引擎按字符袋打分),高于默认阈值
/// 0.45,所以检索必然命中(阈值本身由单元测试覆盖,这里要验的是**注入**)。
const String kKbTitle = '产品手册';
const String kKbText = '语音对话系统由离线识别与离线合成两部分组成。';
const String kKbQuery = '语音对话系统由哪两部分组成';

/// 挂在说话人"张三"名下的一条长期记忆。
const String kMem = '偏好简洁回答';

/// 更早轮次的滚动摘要(假 LLM 直接吐出它)。
const String kSummary = '用户先问了模型下载失败的原因';

const String kReplyKnown = '分离线识别与离线合成两块';
const String kReplyUnknown = '我不太清楚';

void main() {
  patrolTest('上下文注入:知识库 + 该说话人记忆 + 会话摘要进入提示词;未注册者零记忆', ($) async {
    final sessionStore = MemorySessionMemoryStore();
    // 显式给一个**可变**列表:默认值是 `const []`,测试中途改不了(会抛
    // "Cannot clear an unmodifiable list")。本用例要在"摘要 / 回复 / 未知说话人"
    // 三种回复之间切换。
    final llm = FakeLlmClient(chunks: <String>[]);
    final speakerEngine = FakeSpeakerEngine()..nextName = '张三';
    final vad = FakeVadEngine();
    final asr = FakeAsrEngine()..nextText = kKbQuery;

    final deps = await buildPatrolTestDeps(
      llmClient: llm,
      vadEngine: vad,
      asrEngine: asr,
      speakerEngine: speakerEngine,
      sessionMemoryStore: sessionStore,
    );
    await deps.conversationService.downloadInitialModels(null);
    await deps.settings.setLlmApiKey('k');

    // ① 嵌入模型(走新的多文件 raw 下载)+ 一份文档,并等索引完成。
    await deps.modelManager
        .downloadModel(ModelCatalog.byId(kDefaultEmbeddingModelId)!);
    await deps.knowledgeService!.importText(title: kKbTitle, text: kKbText);
    await deps.knowledgeService!.startBackfill();
    expect(deps.knowledgeService!.documents.single.isIndexed, isTrue,
        reason: '文档必须先索引完,检索才可能命中');

    // ② 注册说话人 + 记一条长期记忆。
    //    此刻嵌入会话已被索引加载,所以这条记忆会带上向量(否则检索不到它)。
    await deps.modelManager
        .downloadModel(ModelCatalog.byId(kLegacyVoiceprintModelId)!);
    await deps.voiceprintService.enroll(
      name: '张三',
      note: '偏好中文短句',
      samples: [Float32List(16000)],
    );
    await deps.memoryService!.remember(speaker: '张三', content: kMem);
    expect(await deps.memoryService!.listFor('张三'), hasLength(1));

    // ③ 短期记忆:先确定会话段 id(后用同一个 id 才能被注入),再塞 10 条
    //    "更早说过的话",做一次滚动摘要。
    final now = DateTime.now().millisecondsSinceEpoch;
    final sid = deps.sessionMemoryService!.sessionIdAt(now);
    for (var i = 0; i < 10; i++) {
      sessionStore.addMessage(
        sessionId: sid,
        content: '更早的第$i轮对话',
        createdAt: now - 60000 + i * 1000,
      );
    }
    llm.chunks
      ..clear()
      ..add(kSummary);
    expect(await deps.sessionMemoryService!.maybeSummarize(sessionId: sid), isTrue,
        reason: '攒够 10 条就该做一次增量摘要');
    expect(await deps.sessionMemoryService!.summaryFor(sid), kSummary);

    // ── 张三开口:三块内容都该进提示词 ──────────────────────────────
    await $.pumpWidgetAndSettle(
      RepaintBoundary(
        key: screenshotBoundaryKey,
        child: TtsDemoApp(dependencies: deps),
      ),
    );
    await $(#tabConversation).tap();
    await $.pumpAndSettle();
    await $(#conversationToggleButton).tap();
    await $.pumpAndSettle();

    llm.chunks
      ..clear()
      ..add(kReplyKnown);
    vad.emitSegment(Float32List(1600));
    await $(RegExp(kReplyKnown))
        .waitUntilVisible(timeout: const Duration(seconds: 20));
    await takeScreenshot($.tester, '01_reply_with_context');

    String lastPrompt() =>
        llm.capturedMessages.last.map((m) => m.content).join('\n');

    final known = lastPrompt();
    expect(known, contains('当前说话人: 张三'));
    expect(known, contains('说话人备注: 偏好中文短句'),
        reason: '身份与备注是固定段,必须注入');
    expect(known, contains('【已知资料】'), reason: '知识库片段应注入');
    expect(known, contains('《$kKbTitle》'), reason: '片段要带来源标题');
    expect(known, contains('离线识别'), reason: '注入的应是**检索命中的片段正文**');
    expect(known, contains('【关于当前说话人的长期记忆】'));
    expect(known, contains(kMem));
    expect(known, contains('【本次会话早前摘要】'));
    expect(known, contains(kSummary));
    // 回复会被 TTS 朗读:提示词必须要求不要念出引用标记,否则用户会听见"方括号一"。
    expect(known, contains('不要念出'),
        reason: '语音场景专属约束:防朗读噪音');

    // ── 未注册说话人:零长期记忆(跨人隔离硬约束)────────────────────
    await waitForCondition(
      $,
      what: '第一轮播报结束、回到监听态',
      ready: () async =>
          deps.conversationService.phase == ConversationPhase.listening,
    );
    speakerEngine.nextName = ''; // 识别失败 = 未知说话人

    llm.chunks
      ..clear()
      ..add(kReplyUnknown);
    vad.emitSegment(Float32List(1600));
    await $(RegExp(kReplyUnknown))
        .waitUntilVisible(timeout: const Duration(seconds: 20));
    await takeScreenshot($.tester, '02_unknown_speaker_reply');

    final unknown = lastPrompt();
    expect(unknown, contains('当前说话人: 未知用户'));
    expect(unknown, contains('【已知资料】'),
        reason: '知识库与说话人无关,应照常注入');
    expect(unknown, isNot(contains('【关于当前说话人的长期记忆】')),
        reason: '未知说话人不得注入任何长期记忆');
    expect(unknown, isNot(contains(kMem)),
        reason: '不能把张三的记忆泄漏给未注册者 —— 这是本版唯一的隔离保证');
    expect(unknown, contains(kSummary),
        reason: '摘要属于"这场会话"而非某个人,按设计仍应注入(只有长期记忆按人隔离)');

    deps.conversationService.dispose();
    await deps.streamingService.disposeAll();
  });
}
