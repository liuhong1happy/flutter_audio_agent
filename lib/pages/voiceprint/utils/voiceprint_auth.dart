/// 声纹写操作前的设备认证守卫(录入 / 删除 / 调阈值共用)。
///
/// ⚠️ 便利性保护,不是安全边界:嵌入明文落盘、3 秒录音即可重放通过、本 app
/// 自带的声音克隆也能合成授权人声音。详见 [AppLockService] 的说明。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tts_demo/data/app_dependencies.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';

/// 请求设备认证。返回 true 表示可以继续执行写操作。
///
/// - 设置里关掉保护 → 直接放行;
/// - 设备不具备认证能力 → 弹说明对话框,由用户**显式**关闭保护,绝不静默放行;
/// - 用户取消 / 认证失败 → 返回 false,不弹错误(取消是正常操作)。
Future<bool> ensureVoiceprintAuth(BuildContext context, {String? reason}) async {
  final l10n = AppLocalizations.of(context);
  final settings = context.read<TtsSettings>();
  final lock = context.read<AppDependencies>().appLock;

  if (!settings.requireAuthForEnroll) return true;

  if (!await lock.isSupported()) {
    if (!context.mounted) return false;
    final disable = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.authUnavailableTitle),
        content: Text(l10n.authUnavailableBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const ValueKey('disableAuthButton'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.authDisableProtection),
          ),
        ],
      ),
    );
    if (disable == true) await settings.setRequireAuthForEnroll(false);
    return false;
  }

  return lock.ensureUnlocked(reason ?? l10n.enrollAuthReason);
}
