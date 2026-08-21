/// 自定义 TTS 设置页(需求 3)。
///
/// 选择已下载模型、多音色说话人 sid、语速、句间静音、线程数、
/// 下载镜像与自动滚动开关。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/model_catalog.dart';
import '../data/model_manager.dart';
import '../l10n/app_localizations.dart';
import '../models/tts_settings.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

class TtsSettingsPage extends StatelessWidget {
  const TtsSettingsPage({super.key, this.onNavigateToModel});

  /// "去下载"时回调(由 MainShell 切换到模型 Tab)。
  final VoidCallback? onNavigateToModel;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<TtsSettings>();
    final manager = context.watch<ModelManager>();
    final l10n = AppLocalizations.of(context);

    // 已下载模型列表。
    final downloadedModels = ModelCatalog.all
        .where((m) => manager.isDownloaded(m.id))
        .toList();
    final selectedModel = ModelCatalog.byId(settings.selectedModelId);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionLabel(l10n.sectionModel),
          if (downloadedModels.isEmpty)
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(l10n.noModelDownloaded),
                subtitle: Text(l10n.noModelHint),
                trailing: TextButton(
                  onPressed: () => onNavigateToModel?.call(),
                  child: Text(l10n.goModel),
                ),
              ),
            )
          else
            DropdownButtonFormField<String>(
              key: const ValueKey('modelSelector'),
              initialValue: selectedModel?.id,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.selectModelLabel,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final m in downloadedModels)
                  DropdownMenuItem(
                    value: m.id,
                    child: Text(
                      l10n.modelSpeakerCount(m.displayName, m.speakers),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (id) => settings.selectModel(id),
            ),
          const SizedBox(height: 8),
          if (selectedModel == null)
            Text(
              l10n.modelNotSelected,
              style: AppText.caption.copyWith(color: AppColors.danger),
            ),
          if (selectedModel != null && selectedModel.speakers > 1) ...[
            const SizedBox(height: 16),
            _SectionLabel(l10n.speakerLabel(settings.sid)),
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
          _SectionLabel(l10n.speedLabel(settings.speed.toStringAsFixed(2))),
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
          _SectionLabel(
            l10n.silenceLabel((settings.silenceScale * 100).round()),
          ),
          Slider(
            key: const ValueKey('silenceSlider'),
            value: settings.silenceScale,
            min: 0,
            max: 1.0,
            divisions: 20,
            onChanged: (v) => settings.setSilenceScale(v),
          ),
          const SizedBox(height: 16),
          _SectionLabel(l10n.threadLabel(settings.numThreads)),
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
          _SectionLabel(l10n.downloadSource),
          _MirrorSourcePicker(settings: settings),
          const SizedBox(height: 16),
          SwitchListTile(
            key: const ValueKey('autoScrollSwitch'),
            title: Text(l10n.autoScroll),
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
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        text,
        style: AppText.headline.copyWith(color: AppColors.inkPrimary),
      ),
    );
  }
}

/// 下载源选择:自动(代理+直连回退)或自定义镜像前缀(可输入任意前缀)。
class _MirrorSourcePicker extends StatefulWidget {
  const _MirrorSourcePicker({required this.settings});

  final TtsSettings settings;

  @override
  State<_MirrorSourcePicker> createState() => _MirrorSourcePickerState();
}

class _MirrorSourcePickerState extends State<_MirrorSourcePicker> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.settings.mirrorPrefix);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isCustom => widget.settings.mirrorPrefix.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: const ValueKey('mirrorSelector'),
          initialValue: _isCustom ? 'custom' : 'auto',
          decoration: InputDecoration(
            labelText: l10n.mirrorSourceLabel,
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem(value: 'auto', child: Text(l10n.mirrorAuto)),
            DropdownMenuItem(value: 'custom', child: Text(l10n.mirrorCustom)),
          ],
          onChanged: (v) {
            if (v == 'custom') {
              widget.settings.setMirrorPrefix(
                _controller.text.trim().isNotEmpty
                    ? _controller.text.trim()
                    : 'https://ghfast.top/',
              );
            } else {
              widget.settings.setMirrorPrefix('');
            }
          },
        ),
        if (_isCustom) ...[
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: const ValueKey('mirrorPrefixInput'),
            controller: _controller,
            decoration: InputDecoration(
              labelText: l10n.mirrorPrefixLabel,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => widget.settings.setMirrorPrefix(v.trim()),
          ),
        ],
      ],
    );
  }
}
