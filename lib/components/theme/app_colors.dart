/// 设计令牌:色彩(科技蓝主题)。
///
/// 语义化命名(表达用途);基础结构参考 masrobo design-system,主强调改为科技蓝。
/// 页面背景 #F7F7F7 · Tab 白底 · 选中图标/主题色 = 科技蓝。
library;

import 'package:flutter/material.dart';

abstract final class AppColors {
  // ── 中性 / 表面 ─────────────────────────────────────────────────────
  /// 页面画布(#F7F7F7)。
  static const Color bg = Color(0xFFF7F7F7);

  /// 卡片 / 输入 / 弹层(Tab 白底)。
  static const Color surface = Color(0xFFFFFFFF);

  /// 输入内陷 / 分组底。
  static const Color surfaceSunken = Color(0xFFF0F0F0);

  /// 极弱分隔线(尽量用留白替代)。
  static const Color hairline = Color(0xFFECECEC);

  // ── 文字 ───────────────────────────────────────────────────────────
  /// 标题 / 主文字。
  static const Color inkPrimary = Color(0xFF1F2329);

  /// 正文次要。
  static const Color inkSecondary = Color(0xFF6B7076);

  /// 占位 / 说明。
  static const Color inkTertiary = Color(0xFF9A9FA6);

  /// 禁用。
  static const Color inkDisabled = Color(0xFFC4C8CC);

  // ── 强调(科技蓝) ───────────────────────────────────────────────────
  /// 主题色 / 主按钮 / 关键强调(科技蓝)。
  static const Color accent = Color(0xFF1677FF);

  /// 强调之上的文字。
  static const Color onAccent = Color(0xFFFFFFFF);

  /// 选中态 / 高亮底(淡科技蓝)。
  static const Color accentWeak = Color(0xFFE8F1FF);

  // ── 状态 ───────────────────────────────────────────────────────────
  /// 在线 / 成功。
  static const Color success = Color(0xFF52C41A);

  /// 警告。
  static const Color warn = Color(0xFFFAAD14);

  /// 错误 / 危险操作。
  static const Color danger = Color(0xFFFF4D4F);
}
