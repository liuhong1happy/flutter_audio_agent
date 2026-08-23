/// 设计令牌:间距 / 圆角 / 阴影。
///
/// 8pt 栅格,杜绝随手值。规范来源 neme-ai-app design-system。
library;

import 'package:flutter/material.dart';

/// 间距刻度(4 基):4 · 8 · 12 · 16 · 20 · 24 · 32 · 40。
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20; // 页面横向留白
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double xxxxl = 40;
}

/// 圆角刻度:sm 8 · md 12 · lg 16;卡片 14 / 输入 10 / 按钮 12。
abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double card = 14;
  static const double input = 10;
  static const double button = 12;
}

/// 阴影:优先“平面 + 发丝线”,阴影仅浮层用。
abstract final class AppShadow {
  /// 卡片默认(无阴影,靠留白/hairline 分隔)。
  static const List<BoxShadow> e0 = [];

  /// 需微抬起的卡片。
  static const List<BoxShadow> e1 = [
    BoxShadow(
      color: Color(0x0A1F1D1A), // rgba(31,29,26,.04)
      blurRadius: 2,
      offset: Offset(0, 1),
    ),
  ];

  /// 弹层 / 底部弹窗 / Toast。
  static const List<BoxShadow> e2 = [
    BoxShadow(
      color: Color(0x1A1F1D1A), // rgba(31,29,26,.10)
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];
}
