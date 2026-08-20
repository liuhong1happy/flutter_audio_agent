/// 自定义 TTS 设置页(需求 3)。
///
/// 选择已下载模型、多音色说话人 sid、语速、句间静音、线程数、
/// 下载镜像与自动滚动开关。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/model_catalog.dart';
import '../data/model_manager.dart';
import '../models/tts_settings.dart';

class TtsSettingsPage extends StatelessWidget {
  const TtsSettingsPage({super.key, this.onNavigateToModel});

  /// "去下载"时回调(由 MainShell 切换到模型 Tab)。
  final VoidCallback? onNavigateToModel;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<TtsSettings>();
    final manager = context.watch<ModelManager>();

    // 已下载模型列表。
    final downloadedModels = ModelCatalog.all
        .where((m) => manager.isDownloaded(m.id))
        .toList();
    final selectedModel = ModelCatalog.byId(settings.selectedModelId);

    return Scaffold(
      appBar: AppBar(title: const Text('TTS 设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionLabel('模型'),
          if (downloadedModels.isEmpty)
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('尚未下载任何模型'),
                subtitle: const Text('先到模型管理页下载一个模型,再回来选择。'),
                trailing: TextButton(
                  onPressed: () => onNavigateToModel?.call(),
                  child: const Text('去下载'),
                ),
              ),
            )
          else
            DropdownButtonFormField<String>(
              key: const ValueKey('modelSelector'),
              initialValue: selectedModel?.id,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '选择模型',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final m in downloadedModels)
                  DropdownMenuItem(
                    value: m.id,
                    child: Text(
                      '${m.displayName} (${m.speakers} 音色)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (id) => settings.selectModel(id),
            ),
          const SizedBox(height: 8),
          if (selectedModel == null)
            Text(
              '未选择模型,合成前需要先选择。',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (selectedModel != null && selectedModel.speakers > 1) ...[
            const SizedBox(height: 16),
            _SectionLabel('说话人 (sid ${settings.sid})'),
            Slider(
              key: const ValueKey('sidSlider'),
              value: settings.sid.toDouble(),
              min: 0,
              max: (selectedModel.speakers - 1).toDouble(),
              divisions: selectedModel.speakers > 20
                  ? 20
                  : (selectedModel.speakers - 1).clamp(1, 20),
              label: '${settings.sid}',
              onChanged: (v) => settings.setSid(v.round()),
            ),
          ],
          const SizedBox(height: 16),
          _SectionLabel('语速 ${settings.speed.toStringAsFixed(2)}x'),
          Slider(
            key: const ValueKey('speedSlider'),
            value: settings.speed,
            min: 0.5,
            max: 2.0,
            divisions: 30,
            label: '${settings.speed.toStringAsFixed(2)}x',
            onChanged: (v) => settings.setSpeed(v),
          ),
          const SizedBox(height: 16),
          _SectionLabel('句间静音 ${(settings.silenceScale * 100).round()}%'),
          Slider(
            key: const ValueKey('silenceSlider'),
            value: settings.silenceScale,
            min: 0,
            max: 1.0,
            divisions: 20,
            onChanged: (v) => settings.setSilenceScale(v),
          ),
          const SizedBox(height: 16),
          _SectionLabel('推理线程 ${settings.numThreads}'),
          SegmentedButton<int>(
            key: const ValueKey('threadSelector'),
            segments: const [
              ButtonSegment(value: 1, label: Text('1')),
              ButtonSegment(value: 2, label: Text('2')),
              ButtonSegment(value: 4, label: Text('4')),
            ],
            selected: {settings.numThreads},
            onSelectionChanged: (s) => settings.setNumThreads(s.first),
          ),
          const SizedBox(height: 16),
          _SectionLabel('下载镜像'),
          DropdownButtonFormField<String>(
            key: const ValueKey('mirrorSelector'),
            initialValue: settings.mirrorPrefix.isEmpty ? 'direct' : 'mirror',
            decoration: const InputDecoration(
              labelText: '下载源(国内网络慢时可切换镜像)',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: 'direct',
                child: Text('GitHub 直连(默认)'),
              ),
              DropdownMenuItem(
                value: 'mirror',
                child: Text('镜像(ghproxy 前缀)'),
              ),
            ],
            onChanged: (v) {
              settings.setMirrorPrefix(
                v == 'mirror' ? 'https://ghproxy.net/' : '',
              );
            },
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            key: const ValueKey('autoScrollSwitch'),
            title: const Text('自动滚动跟随朗读'),
            value: settings.autoScroll,
            onChanged: (v) => settings.setAutoScroll(v),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
