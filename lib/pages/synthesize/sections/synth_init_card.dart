/// 合成页初始化卡片(没有可用模型时展示):下载并启用一个语音合成模型。
///
/// 与对话页的 `InitCard` 刻意不复用:那边是"三件套多个模型 + 勾选 + 进度",
/// 这边是"选一个模型",数据形状与动作(`downloadModel` + `selectModel`)都不同。
///
/// ⚠️ 两处硬约束(踩过):
/// 1. 主按钮 key **不能叫 `initDownloadButton`** —— `IndexedStack` 会同时构建
///    三个 Tab,而对话页初始化卡片用的就是那个 key,重名会让对话页的
///    `findsOneWidget/findsNothing` 断言直接挂。
/// 2. 静置态**不能出现不确定进度条**(`value: null`),否则用到
///    `pumpAndSettle` 的测试会永远收敛不了。
library;

import 'package:flutter/material.dart';

import 'package:flutter_tts_demo/components/theme/app_colors.dart';
import 'package:flutter_tts_demo/components/theme/app_spacing.dart';
import 'package:flutter_tts_demo/components/theme/app_text.dart';
import 'package:flutter_tts_demo/data/model_manager.dart';
import 'package:flutter_tts_demo/data/models/tts_model.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';

class SynthInitCard extends StatelessWidget {
  const SynthInitCard({
    super.key,
    required this.target,
    required this.selected,
    required this.state,
    required this.onDownload,
    required this.onCancel,
    required this.onOpenSettings,
  });

  /// 待下载/待启用的模型。
  final TtsModel target;

  /// 该模型是否已被选中(区分"从未选过"与"选了但没下载"两种文案)。
  final bool selected;

  final ModelDownloadState state;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final busy = state.isDownloading || state.status == DownloadStatus.extracting;
    final failed = state.status == DownloadStatus.error;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.initSynthTitle, style: AppText.headline),
            const SizedBox(height: AppSpacing.sm),
            Text(
              selected ? l10n.initSynthNotDownloaded : l10n.initSynthNotSelected,
              style: AppText.caption,
            ),
            const SizedBox(height: AppSpacing.md),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                busy ? Icons.downloading : Icons.record_voice_over_outlined,
                color: AppColors.accent,
              ),
              title: Text(target.displayName, style: AppText.body),
              subtitle: Text(target.sizeLabel, style: AppText.caption),
            ),
            const SizedBox(height: AppSpacing.md),
            if (busy) ...[
              // 确定值进度(pumpAndSettle 友好)。
              LinearProgressIndicator(
                value: state.status == DownloadStatus.extracting
                    ? 1.0
                    : state.progress,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.initProgress((state.progress * 100).round()),
                style: AppText.caption,
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton(
                key: const ValueKey('synthInitCancelButton'),
                onPressed: onCancel,
                child: Text(l10n.cancel),
              ),
            ] else ...[
              if (failed) ...[
                Text(
                  state.error ?? l10n.genericError,
                  style: AppText.caption.copyWith(color: AppColors.danger),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              FilledButton.icon(
                key: const ValueKey('synthInitDownloadButton'),
                onPressed: onDownload,
                icon: const Icon(Icons.download),
                label: Text(
                  failed ? l10n.initRetry : l10n.initSynthDownloadAndEnable,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              key: const ValueKey('synthMoreModelsButton'),
              onPressed: onOpenSettings,
              child: Text(l10n.initSynthMoreModels),
            ),
          ],
        ),
      ),
    );
  }
}
