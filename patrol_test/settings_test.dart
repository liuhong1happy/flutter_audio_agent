/// 设置页端到端测试:大类列表 → 各子页配置 + 各自模型下载 + 清理缓存。
///
/// 运行方式(需已连接 Android 设备/模拟器):
///   patrol test -t patrol_test/settings_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_tts_demo/app.dart';
import 'package:patrol/patrol.dart';

import 'screenshot_helper.dart';
import 'test_deps.dart';

void main() {
  patrolTest('设置页:大类列表 → 各子页配置 + 清理缓存', ($) async {
    final deps = await buildPatrolTestDeps();
    await $.pumpWidgetAndSettle(
      RepaintBoundary(
        key: screenshotBoundaryKey,
        child: TtsDemoApp(dependencies: deps),
      ),
    );

    // 设置 Tab:大类列表。
    await $(#tabSettings).tap();
    await $.pumpAndSettle();
    await takeScreenshot($.tester, '01_settings_categories');

    // 语音合成 (TTS)。
    await $(RegExp('TTS')).tap();
    await $.pumpAndSettle();
    await takeScreenshot($.tester, '02_settings_tts');
    await $.tester.pageBack();
    await $.pumpAndSettle();

    // 语音识别 (ASR)。
    await $(RegExp('ASR')).tap();
    await $.pumpAndSettle();
    await takeScreenshot($.tester, '03_settings_asr');
    await $.tester.pageBack();
    await $.pumpAndSettle();

    // 语音活动检测 (VAD)。
    await $(RegExp('VAD')).tap();
    await $.pumpAndSettle();
    await takeScreenshot($.tester, '04_settings_vad');
    await $.tester.pageBack();
    await $.pumpAndSettle();

    // 声纹识别 (Voiceprint)。
    await $(RegExp('Voiceprint')).tap();
    await $.pumpAndSettle();
    await takeScreenshot($.tester, '05_settings_voiceprint');
    // 注册说话人弹窗。
    await $(#enrollSpeakerButton).tap();
    await $.pumpAndSettle();
    await takeScreenshot($.tester, '05b_enroll_speaker');
    await $.tester.pageBack(); // 关闭弹窗。
    await $.pumpAndSettle();
    await $.tester.pageBack(); // 返回大类列表。
    await $.pumpAndSettle();

    // 大模型 (LLM)。
    await $(RegExp('LLM')).tap();
    await $.pumpAndSettle();
    await takeScreenshot($.tester, '06_settings_llm');
    await $.tester.pageBack();
    await $.pumpAndSettle();

    // 通用 → 清理缓存。
    await $(RegExp('General')).tap();
    await $.pumpAndSettle();
    await takeScreenshot($.tester, '07_settings_general');
    await $(#clearCacheButton).tap();
    await $(#confirmClearButton).waitUntilVisible();
    await takeScreenshot($.tester, '08_clear_cache_dialog');
    await $(#confirmClearButton).tap();
    await $.pumpAndSettle();
    await takeScreenshot($.tester, '09_cache_cleared');

    await deps.streamingService.disposeAll();
  });
}
