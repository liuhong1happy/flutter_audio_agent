/// Patrol 测试截图助手。
///
/// patrol 4.9 对 Android 无内置 Dart 截图 API,这里用 Flutter 标准做法:
/// 把被测 App 包在 `RepaintBoundary(key: screenshotBoundaryKey)` 中,
/// 通过 [takeScreenshot] 把该边界渲染为 PNG 保存到应用文档目录
/// `.../screenshots/<name>.png`,供后续用 adb 拉取或应用内查看。
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';

/// 测试里包裹 App 的 RepaintBoundary 的 key。
final GlobalKey screenshotBoundaryKey = GlobalKey();

/// 截取 [screenshotBoundaryKey] 所在边界的当前画面,保存为 PNG。
///
/// 截图失败只打印日志,不会让测试失败。
Future<void> takeScreenshot(WidgetTester tester, String name) async {
  try {
    await tester.pumpAndSettle();
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
