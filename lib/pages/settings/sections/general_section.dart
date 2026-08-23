/// 通用设置段:下载源 + 自动滚动 + 清理缓存。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tts_demo/data/app_dependencies.dart';
import 'package:flutter_tts_demo/components/theme/app_colors.dart';
import 'package:flutter_tts_demo/components/theme/app_text.dart';
import 'package:flutter_tts_demo/data/model_manager.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';

import '../components/settings_widgets.dart';

class GeneralSection extends StatelessWidget {
  const GeneralSection({super.key});

  Future<void> _clearAllCaches(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final deps = context.read<AppDependencies>();
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
            key: const ValueKey('confirmClearButton'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.confirmClear),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await deps.clearAllData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<TtsSettings>();
    final manager = context.watch<ModelManager>();
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.sectionGeneral)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader(l10n.downloadSource, Icons.cloud_download_outlined),
          MirrorSourcePicker(settings: settings),
          const SectionDivider(),
          SwitchListTile(
            key: const ValueKey('autoScrollSwitch'),
            title: Text(l10n.autoScroll),
            value: settings.autoScroll,
            onChanged: (v) => settings.setAutoScroll(v),
          ),
          const SectionDivider(),
          SectionHeader(l10n.clearAll, Icons.cleaning_services_outlined),
          FutureBuilder<int>(
            future: manager.totalBytesOnDisk(),
            builder: (context, snap) {
              final mb = (snap.data ?? 0) / (1024 * 1024);
              return Text(
                l10n.diskUsage(mb.toStringAsFixed(1)),
                style: AppText.caption.copyWith(color: AppColors.inkTertiary),
              );
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('clearCacheButton'),
            onPressed: () => _clearAllCaches(context),
            icon: const Icon(Icons.cleaning_services_outlined),
            label: Text(l10n.clearAll),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
