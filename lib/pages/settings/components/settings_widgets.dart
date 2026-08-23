/// 设置页共享组件:分区标题 / 子项标签 / 分隔线 / 管理入口 / 文本输入 / 镜像选择 / 模型下载 / 大类入口。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tts_demo/components/theme/app_colors.dart';
import 'package:flutter_tts_demo/components/theme/app_spacing.dart';
import 'package:flutter_tts_demo/components/theme/app_text.dart';
import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/data/model_manager.dart';
import 'package:flutter_tts_demo/data/models/tts_model.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';

/// 大类入口 ListTile。
class CategoryTile extends StatelessWidget {
  const CategoryTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.accent),
      title: Text(title, style: AppText.bodyStrong),
      trailing: const Icon(Icons.chevron_right, color: AppColors.inkTertiary),
      onTap: onTap,
    );
  }
}

/// 分区标题(带图标)。
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, this.icon, {super.key});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.accent),
          const SizedBox(width: 6),
          Text(text, style: AppText.headline.copyWith(color: AppColors.inkPrimary)),
        ],
      ),
    );
  }
}

/// 子项标签(展示当前值)。
class SettingLabel extends StatelessWidget {
  const SettingLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(text, style: AppText.bodyStrong.copyWith(color: AppColors.inkSecondary)),
    );
  }
}

/// 分区之间的分隔线。
class SectionDivider extends StatelessWidget {
  const SectionDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      const Padding(padding: EdgeInsets.only(top: 16), child: Divider(height: 1));
}

/// 管理入口(如声纹管理 / 克隆音管理)。
class ManageEntry extends StatelessWidget {
  const ManageEntry({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.inkSecondary),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right, color: AppColors.inkTertiary),
      onTap: onTap,
    );
  }
}

/// 文本输入设置项(自管理 controller)。
class TextFieldSetting extends StatefulWidget {
  const TextFieldSetting({
    super.key,
    required this.label,
    required this.initial,
    required this.onChanged,
    this.obscure = false,
    this.maxLines = 1,
  });

  final String label;
  final String initial;
  final ValueChanged<String> onChanged;
  final bool obscure;
  final int maxLines;

  @override
  State<TextFieldSetting> createState() => _TextFieldSettingState();
}

class _TextFieldSettingState extends State<TextFieldSetting> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _controller,
        obscureText: widget.obscure,
        maxLines: widget.maxLines,
        minLines: 1,
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}

/// 下载源选择:自动 / 自定义镜像前缀。
class MirrorSourcePicker extends StatefulWidget {
  const MirrorSourcePicker({super.key, required this.settings});

  final TtsSettings settings;

  @override
  State<MirrorSourcePicker> createState() => _MirrorSourcePickerState();
}

class _MirrorSourcePickerState extends State<MirrorSourcePicker> {
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

/// 按 kind 的模型下载列表。
class ModelDownloadList extends StatelessWidget {
  const ModelDownloadList({super.key, required this.kind});

  final ModelKind kind;

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<ModelManager>();
    final l10n = AppLocalizations.of(context);
    final models = ModelCatalog.all.where((m) => m.kind == kind).toList();

    return Column(
      children: [
        for (final m in models)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(m.displayName, style: AppText.body),
            subtitle: Text(m.sizeLabel, style: AppText.caption),
            trailing: manager.isDownloaded(m.id)
                ? const Icon(Icons.check_circle, color: AppColors.success)
                : manager.stateOf(m).isDownloading
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          value: manager.stateOf(m).progress,
                          strokeWidth: 2,
                        ),
                      )
                    : FilledButton.tonal(
                        onPressed: () => manager.downloadModel(m),
                        child: Text(l10n.download),
                      ),
          ),
      ],
    );
  }
}
