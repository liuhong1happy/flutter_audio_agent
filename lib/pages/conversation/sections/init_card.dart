/// 对话初始化卡片(未就绪时展示):按模式与缺口显示"缺什么补什么"。
///
/// 两种模式的依赖不同:
/// - **文本模式**只用 LLM,所以只显示"配置大模型",**不给任何模型下载入口**。
/// - **音频模式**要三件套 + LLM,所以两块都可能出现。
///
/// 特别处理一种情况:模型已就绪但 LLM 没配 —— 这时**不能**还显示一个全部
/// 打勾的下载列表,那样用户没有任何前进路径。改为显示"还差配置大模型"。
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

import '../conversation_mode.dart';

class InitCard extends StatelessWidget {
  const InitCard({
    super.key,
    required this.mode,
    required this.modelsReady,
    required this.llmReady,
    required this.downloading,
    required this.progress,
    required this.onDownload,
    required this.onConfigureLlm,
  });

  final ConversationMode mode;

  /// 三件套是否就绪(由页面传 `service.isReadyForConversation`)。
  final bool modelsReady;

  /// 大模型是否已配置(由页面传 `settings.isLlmConfigured`)。
  final bool llmReady;

  final bool downloading;
  final double progress;
  final VoidCallback onDownload;
  final VoidCallback onConfigureLlm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final manager = context.watch<ModelManager>();

    final items = kDefaultConversationModelIds.values
        .map(ModelCatalog.byId)
        .whereType<TtsModel>()
        .toList();

    // 音频模式且模型没齐 → 才显示三件套下载块。
    final showModels = mode == ConversationMode.audio && !modelsReady;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showModels) ...[
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
                // 必须确定值进度:不确定动画会让 pumpAndSettle 永不收敛。
                LinearProgressIndicator(value: progress),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.initProgress((progress * 100).round()),
                  style: AppText.caption,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              FilledButton.icon(
                key: const ValueKey('initDownloadButton'),
                onPressed: downloading ? null : onDownload,
                icon: const Icon(Icons.download),
                label: Text(
                  downloading ? l10n.recording : l10n.downloadInitialModels,
                ),
              ),
            ],
            if (showModels && !llmReady) const SizedBox(height: AppSpacing.lg),
            // 大模型块:两种模式都可能出现,文案按模式与缺口区分。
            if (!llmReady) ...[
              Text(
                mode == ConversationMode.text
                    ? l10n.initLlmTitle
                    : (modelsReady ? l10n.initLlmOnlyLeft : l10n.initLlmMissing),
                style: showModels ? AppText.body : AppText.headline,
              ),
              if (mode == ConversationMode.text) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(l10n.initTextModeHint, style: AppText.caption),
              ],
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                key: const ValueKey('configureLlmButton'),
                onPressed: onConfigureLlm,
                icon: const Icon(Icons.smart_toy_outlined),
                label: Text(l10n.goConfigureLlm),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
