/// 模型管理测试:目录渲染、清理全部缓存(含截图)。
///
/// 运行方式(需已连接 Android 设备/模拟器):
///   patrol test -t patrol_test/model_manage_test.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_tts_demo/app.dart';
import 'package:patrol/patrol.dart';

import 'screenshot_helper.dart';
import 'test_deps.dart';

void main() {
  patrolTest('模型目录渲染与清理缓存', ($) async {
    final deps = await buildPatrolTestDeps();
    await $.pumpWidgetAndSettle(
      RepaintBoundary(
        key: screenshotBoundaryKey,
        child: TtsDemoApp(dependencies: deps),
      ),
    );
    await takeScreenshot($.tester, '01_home');

    // 进入模型管理页。
    await $(#modelManageButton).tap();
    await $.pumpAndSettle();
    await takeScreenshot($.tester, '02_model_list');

    // 目录条目渲染。
    await $(RegExp('Piper 晓雅')).waitUntilVisible();
    await $(#clearCacheButton).waitUntilVisible();

    // 清理全部缓存(弹出确认对话框)。
    await $(#clearCacheButton).tap();
    await $(RegExp('确认清理')).waitUntilVisible();
    await takeScreenshot($.tester, '03_clear_cache_dialog');
    await $(RegExp('确认清理')).tap();
    await $.pumpAndSettle();
    await takeScreenshot($.tester, '04_cache_cleared');

    // 清理后默认模型回到"未下载"状态,出现"下载"按钮。
    await $(RegExp('下载')).waitUntilVisible(timeout: const Duration(seconds: 10));

    await deps.streamingService.disposeAll();
  });
}
