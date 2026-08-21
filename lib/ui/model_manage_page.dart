/// 模型下载管理页(需求 1 + 6)。
///
/// 展示模型目录、下载/取消/删除模型、清理全部缓存。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/model_catalog.dart';
import '../data/model_manager.dart';
import '../l10n/app_localizations.dart';
import '../models/tts_model.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';

class ModelManagePage extends StatefulWidget {
  const ModelManagePage({super.key});

  @override
  State<ModelManagePage> createState() => _ModelManagePageState();
}

class _ModelManagePageState extends State<ModelManagePage> {
  Future<void> _clearAllCaches(ModelManager manager) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.clearAllTitle),
        content: Text(l10n.clearAllConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.confirmClear),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await manager.clearAllCaches();
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<ModelManager>();
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.modelManageTitle),
        actions: [
          FutureBuilder<int>(
            future: manager.totalBytesOnDisk(),
            builder: (context, snap) {
              final mb = (snap.data ?? 0) / (1024 * 1024);
              return Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    l10n.diskUsage(mb.toStringAsFixed(1)),
                    style: AppText.caption.copyWith(color: AppColors.inkTertiary),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.separated(
              itemCount: ModelCatalog.all.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) => _ModelTile(
                model: ModelCatalog.all[i],
                state: manager.stateOf(ModelCatalog.all[i]),
                isDownloaded: manager.isDownloaded(ModelCatalog.all[i].id),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey('clearCacheButton'),
                  onPressed: () => _clearAllCaches(manager),
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: Text(l10n.clearAll),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.model,
    required this.state,
    required this.isDownloaded,
  });

  final TtsModel model;
  final ModelDownloadState state;
  final bool isDownloaded;

  @override
  Widget build(BuildContext context) {
    final manager = context.read<ModelManager>();
    final l10n = AppLocalizations.of(context);

    final isDownloading = state.isDownloading;
    final progress = state.progress;

    Widget trailing;
    if (isDownloaded) {
      trailing = IconButton(
        tooltip: l10n.deleteModel,
        icon: const Icon(Icons.delete_outline, color: AppColors.danger),
        onPressed: () => manager.removeModel(model),
      );
    } else if (isDownloading) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(value: progress),
          ),
          IconButton(
            tooltip: l10n.cancelDownload,
            icon: const Icon(Icons.close),
            onPressed: () => manager.cancelDownload(model),
          ),
        ],
      );
    } else {
      trailing = FilledButton.tonal(
        onPressed: () => manager.downloadModel(model),
        child: Text(l10n.download),
      );
    }

    return ListTile(
      leading: const Icon(Icons.model_training_outlined),
      title: Text(model.displayName, style: AppText.bodyStrong),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            model.description,
            style: AppText.caption.copyWith(color: AppColors.inkSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${model.sizeLabel} · 采样率 ${(model.sampleRate / 1000).toStringAsFixed(1)}kHz'
            '${model.speakers > 1 ? ' · ${model.speakers} 音色' : ''}'
            ' · ${model.license}',
            style: AppText.caption.copyWith(color: AppColors.inkTertiary),
          ),
          if (state.error != null)
            Text(
              state.error!,
              style: AppText.caption.copyWith(color: AppColors.danger),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      isThreeLine: true,
      trailing: trailing,
    );
  }
}
