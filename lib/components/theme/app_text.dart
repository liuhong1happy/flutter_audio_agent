/// 设计令牌:字体。
///
/// 全局仅 3 个字重(400/500/600),字号收敛到一套;颜色默认 ink.primary,
/// 通过 [secondary] / [tertiary] 切换。规范来源 neme-ai-app design-system。
library;

import 'package:flutter/material.dart';

import 'package:flutter_tts_demo/components/theme/app_colors.dart';

abstract final class AppText {
  /// 大数字 / 欢迎语:28 / 600 / 1.2。
  static const TextStyle display = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: AppColors.inkPrimary,
  );

  /// 页面主标题:20 / 600 / 1.3。
  static const TextStyle title = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.inkPrimary,
  );

  /// 卡片 / 区块标题:17 / 600 / 1.3。
  static const TextStyle headline = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.inkPrimary,
  );

  /// 正文:15 / 400 / 1.5。
  static const TextStyle body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.inkPrimary,
  );

  /// 强调正文:15 / 500 / 1.5。
  static const TextStyle bodyStrong = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.5,
    color: AppColors.inkPrimary,
  );

  /// 按钮 / 标签:13 / 500 / 1.3。
  static const TextStyle label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: AppColors.inkPrimary,
  );

  /// 辅助说明:12 / 400 / 1.4。
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
    color: AppColors.inkPrimary,
  );

  /// 次要文字(ink.secondary)。
  static TextStyle secondary(TextStyle style) =>
      style.copyWith(color: AppColors.inkSecondary);

  /// 三级文字(ink.tertiary)。
  static TextStyle tertiary(TextStyle style) =>
      style.copyWith(color: AppColors.inkTertiary);

  /// 禁用文字(ink.disabled)。
  static TextStyle disabled(TextStyle style) =>
      style.copyWith(color: AppColors.inkDisabled);
}
