/// 应用主题装配(Warm Neutral 暖灰极简)。
///
/// 依据 design-system 落地流程:令牌层 → 装配 ThemeData →
/// 组件主题(按钮/输入/卡片/顶栏/导航栏/分隔线)。规范来源 neme-ai-app。
library;

import 'package:flutter/material.dart';

import 'package:flutter_tts_demo/components/theme/app_colors.dart';
import 'package:flutter_tts_demo/components/theme/app_text.dart';

ThemeData buildAppTheme() {
  final base = ThemeData(useMaterial3: true);
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.accent,
    onPrimary: AppColors.onAccent,
    surface: AppColors.surface,
    onSurface: AppColors.inkPrimary,
    error: AppColors.danger,
    outline: AppColors.hairline,
    outlineVariant: AppColors.hairline,
    secondaryContainer: AppColors.accentWeak,
  );

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: colorScheme,
    textTheme: base.textTheme.copyWith(
      displaySmall: AppText.display,
      titleLarge: AppText.title,
      titleMedium: AppText.headline,
      bodyLarge: AppText.body,
      bodyMedium: AppText.body,
      bodySmall: AppText.caption,
      labelLarge: AppText.label,
      labelMedium: AppText.label,
      labelSmall: AppText.caption,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: AppText.headline,
      iconTheme: IconThemeData(color: AppColors.inkPrimary),
      toolbarHeight: 56,
    ),
    // 主按钮:炭黑底 / 暖白字,圆角 12。
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        disabledBackgroundColor: AppColors.inkDisabled,
        disabledForegroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: AppText.label,
        minimumSize: const Size(64, 48),
      ),
    ),
    // 次按钮:发丝线描边。
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.inkPrimary,
        side: const BorderSide(color: AppColors.hairline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: AppText.label,
        minimumSize: const Size(64, 48),
      ),
    ),
    // 幽灵按钮:无底 / ink.secondary 字。
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.inkSecondary,
        textStyle: AppText.label,
      ),
    ),
    // 输入:内陷底 / 无描边 / 聚焦 1px accent。
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceSunken,
      hintStyle: AppText.body.copyWith(color: AppColors.inkTertiary),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.accent, width: 1),
      ),
    ),
    // 卡片:surface 底 / 圆角 14 / e0。
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
    ),
    // 分隔:尽量用留白,少用线。
    dividerTheme: const DividerThemeData(
      color: AppColors.hairline,
      thickness: 1,
      space: 1,
    ),
    // 底部导航:白底,选中图标 = 科技蓝。
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      elevation: 0,
      height: 64,
      indicatorColor: AppColors.accentWeak,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.inkTertiary,
          size: 24,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => AppText.caption.copyWith(
          color: states.contains(WidgetState.selected)
              ? AppColors.accent
              : AppColors.inkTertiary,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
        ),
      ),
    ),
    // 徽标 / 选择块。
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: AppColors.surface,
      selectedColor: AppColors.accentWeak,
      labelStyle: AppText.label,
      side: const BorderSide(color: AppColors.hairline),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
      linearTrackColor: AppColors.hairline,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.inkPrimary,
      contentTextStyle: TextStyle(color: AppColors.onAccent),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
