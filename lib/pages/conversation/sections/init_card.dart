/// 对话初始化卡片(未就绪时展示):三件套下载 + 一键初始化。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tts_demo/components/theme/app_colors.dart';
import 'package:flutter_tts_demo/components/theme/app_spacing.dart';
import 'package:flutter_tts_demo/components/theme/app_text.dart';
import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/data/model_manager.dart';
import 'package:flutter_tts_demo/data/models/tts_model.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';

class InitCard extends StatelessWidget {
  const InitCard({
    super.key,
    required this.downloading,
    required this.progress,
    required this.onDownload,
  });

  final bool downloading;
  final double progress;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final manager = context.watch<ModelManager>();

    final items = kDefaultConversationModelIds.values
        .map(ModelCatalog.byId)
        .whereType<TtsModel>()
        .toList();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.initModelsTitle, style: AppText.headline),
            const SizedBox(height: AppSpacing.sm),
            Text(l10n.initModelsHint, style: AppText.caption),
            const SizedBox(height: AppSpacing.md),
            for (final m in items)
              ListTile(
                dense: true,
                leading: Icon(
                  manager.isDownloaded(m.id)
                      ? Icons.check_circle_outline
                      : Icons.radio_button_unchecked,
                  color: manager.isDownloaded(m.id)
                      ? AppColors.success
                      : AppColors.inkTertiary,
                ),
                title: Text(m.displayName, style: AppText.body),
                subtitle: Text(m.sizeLabel, style: AppText.caption),
              ),
            const SizedBox(height: AppSpacing.md),
            if (downloading) ...[
              LinearProgressIndicator(value: progress),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.initProgress((progress * 100).round()),
                style: AppText.caption,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              key: const ValueKey('initDownloadButton'),
              onPressed: downloading ? null : onDownload,
              icon: const Icon(Icons.download),
              label: Text(downloading ? l10n.recording : l10n.downloadInitialModels),
            ),
          ],
        ),
      ),
    );
  }
}
