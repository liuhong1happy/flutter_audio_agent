/// Patrol 测试截图助手。
///
/// patrol 4.9 对 Android 无内置 Dart 截图 API,这里用 Flutter 标准做法:
/// 把被测 App 包在 `RepaintBoundary(key: screenshotBoundaryKey)` 中,
/// 通过 [takeScreenshot] 把该边界渲染为 PNG 保存到应用文档目录
/// `.../screenshots/<name>.png`,供后续用 adb 拉取或应用内查看。
///
/// **默认就出图**;要关掉传 `--dart-define=E2E_SCREENSHOTS=false`
/// (或直接用 `sh scripts/patrol_e2e.sh --no-screenshots`)。见 [kScreenshotsEnabled]。
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';

/// 测试里包裹 App 的 RepaintBoundary 的 key。
final GlobalKey screenshotBoundaryKey = GlobalKey();

/// 是否真的截图。**默认开**。
///
/// 关掉:
/// ```
/// patrol test -t patrol_test/knowledge_test.dart --dart-define=E2E_SCREENSHOTS=false
/// sh scripts/patrol_e2e.sh --no-screenshots        # 脚本代传,并同时跳过拉取
/// ```
///
/// ⚠️ 关掉截图时 [takeScreenshot] **仍然会 `pumpAndSettle`**,只是不渲染、不落盘。
/// 这是刻意的:开/关截图不该改变测试的时序与结果 —— 否则"只在某一种模式下才挂"
/// 的用例最难查。
const bool kScreenshotsEnabled = bool.fromEnvironment(
  'E2E_SCREENSHOTS',
  defaultValue: true,
);

/// 关截图后只提示一次,免得每个调用点都刷一行。
bool _disabledNoticePrinted = false;

/// 截取 [screenshotBoundaryKey] 所在边界的当前画面,保存为 PNG。
///
/// 截图失败只打印日志,不会让测试失败(它不是断言手段)。
Future<void> takeScreenshot(WidgetTester tester, String name) async {
  final capturing = kScreenshotsEnabled;
  try {
    await tester.pumpAndSettle();
    if (!capturing) {
      if (!_disabledNoticePrinted) {
        _disabledNoticePrinted = true;
        debugPrint('[screenshot] 已禁用(E2E_SCREENSHOTS=false),本次不再落盘');
      }
      return;
    }
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(screenshotBoundaryKey),
    );
    final image = await boundary.toImage(pixelRatio: 1.0);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/screenshots');
      await dir.create(recursive: true);
      final file = File('${dir.path}/$name.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());
      debugPrint('[screenshot] saved: ${file.path}');
    } finally {
      image.dispose();
    }
  } catch (e) {
    debugPrint('[screenshot] $name 失败: $e');
  }
}
