/// 模型下载管理页(需求 1 + 6)。
///
/// 展示模型目录、下载/取消/删除模型、清理全部缓存。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/model_catalog.dart';
import '../data/model_manager.dart';
import '../models/tts_model.dart';

class ModelManagePage extends StatefulWidget {
  const ModelManagePage({super.key});

  @override
  State<ModelManagePage> createState() => _ModelManagePageState();
}

class _ModelManagePageState extends State<ModelManagePage> {
  Future<void> _clearAllCaches(ModelManager manager) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理全部缓存'),
        content: const Text('将删除所有已下载模型与音频缓存,并重置已下载标记。\n此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认清理'),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('模型管理'),
        actions: [
          FutureBuilder<int>(
            future: manager.totalBytesOnDisk(),
            builder: (context, snap) {
              final mb = (snap.data ?? 0) / (1024 * 1024);
              return Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    '占用 ${mb.toStringAsFixed(1)}MB',
                    style: Theme.of(context).textTheme.bodySmall,
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
                  label: const Text('清理全部缓存(删除所有模型)'),
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

    final isDownloading = state.isDownloading;
    final progress = state.progress;

    Widget trailing;
    if (isDownloaded) {
      trailing = IconButton(
        tooltip: '删除模型',
        icon: const Icon(Icons.delete_outline, color: Colors.red),
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
            tooltip: '取消下载',
            icon: const Icon(Icons.cancel_outlined),
            onPressed: () => manager.cancelDownload(model),
          ),
        ],
      );
    } else {
      trailing = FilledButton.tonal(
        onPressed: () => manager.downloadModel(model),
        child: const Text('下载'),
      );
    }

    return ListTile(
      leading: const Icon(Icons.model_training_outlined),
      title: Text(model.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            model.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${model.sizeLabel} · 采样率 ${(model.sampleRate / 1000).toStringAsFixed(1)}kHz'
            '${model.speakers > 1 ? ' · ${model.speakers} 音色' : ''}'
            ' · ${model.license}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (state.error != null)
            Text(
              state.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
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
