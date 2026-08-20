/// 冒烟测试:输入文本 → 合成 → 朗读视图高亮推进。
///
/// 运行方式(需已连接 Android 设备/模拟器):
///   patrol test -t patrol_test/app_smoke_test.dart
library;

import 'package:flutter_tts_demo/app.dart';
import 'package:patrol/patrol.dart';

import 'test_deps.dart';

void main() {
  patrolTest('输入文本合成,朗读视图高亮推进', ($) async {
    final deps = await buildPatrolTestDeps();
    await $.pumpWidgetAndSettle(TtsDemoApp(dependencies: deps));

    // 输入文本并点击合成。
    await $(#ttsInput).enterText('价格12.5元。拨打110求助。');
    await $(#speakButton).tap();

    // 归一化片段应出现在朗读视图中。
    await $(RegExp('价格十二点五元'))
        .waitUntilVisible(timeout: const Duration(seconds: 15));

    // 状态栏应进入"播放中",说明高亮已随播放推进。
    await $(RegExp('播放中')).waitUntilVisible(timeout: const Duration(seconds: 15));

    await deps.streamingService.disposeAll();
  });
}
