/// 大模型配置的编辑页(新建 / 编辑同页)。
///
/// 表单状态是**本地草稿**,保存时才写回设置 —— 旧版是每敲一个字符就 dispatch
/// 一次(即每次按键写一遍 SharedPreferences),变成列表后那样会把整个列表反复
/// 重写。切服务商会替换草稿里的地址与默认模型,靠 [TextFieldSetting] 的
/// `didUpdateWidget` 让输入框跟着变。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tts_demo/components/theme/app_text.dart';
import 'package:flutter_tts_demo/data/models/llm_config.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';

import '../components/settings_widgets.dart';

class LlmConfigEditPage extends StatefulWidget {
  const LlmConfigEditPage({super.key, this.initial});

  /// null = 新建。
  final LlmConfig? initial;

  @override
  State<LlmConfigEditPage> createState() => _LlmConfigEditPageState();
}

class _LlmConfigEditPageState extends State<LlmConfigEditPage> {
  late final bool _isNew = widget.initial == null;
  late LlmConfig _draft = widget.initial ??
      LlmConfig.fromPreset(
        '${DateTime.now().microsecondsSinceEpoch}',
        llmPresets.first,
      );

  Future<void> _save() async {
    // 地址/Key/模型去掉首尾空白(提示词保留原样,换行与缩进有意义)。
    final config = _draft.copyWith(
      name: _draft.name.trim().isEmpty ? _draft.provider : _draft.name.trim(),
      baseUrl: _draft.baseUrl.trim(),
      apiKey: _draft.apiKey.trim(),
      model: _draft.model.trim(),
    );
    await context.read<TtsSettings>().upsertLlmConfig(config);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final settings = context.read<TtsSettings>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l10n.llmDeleteConfigConfirm(_draft.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const ValueKey('confirmDeleteLlmConfigButton'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await settings.deleteLlmConfig(_draft.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.watch<TtsSettings>();
    // 至少保留一条:只剩这条时不给删,避免"删了又冒出来一条"的怪行为。
    final canDelete = !_isNew && settings.llmConfigs.length > 1;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? l10n.llmNewConfig : l10n.llmEditConfig),
        actions: [
          TextButton(
            key: const ValueKey('saveLlmConfigButton'),
            onPressed: _save,
            child: Text(l10n.save),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFieldSetting(
            key: const ValueKey('llmConfigNameField'),
            label: l10n.llmConfigName,
            initial: _draft.name,
            onChanged: (v) => setState(() => _draft = _draft.copyWith(name: v)),
          ),
          SettingLabel(l10n.llmProvider),
          DropdownButtonFormField<String>(
            key: const ValueKey('llmProviderSelector'),
            // 服务商由 baseUrl 反查(不单独存字段),所以切完地址这里自然跟着变。
            initialValue: providerOfBaseUrl(_draft.baseUrl),
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: [
              for (final p in llmPresets)
                DropdownMenuItem(value: p.name, child: Text(p.name)),
              DropdownMenuItem(
                value: kCustomProvider,
                child: Text(l10n.llmProviderCustom),
              ),
            ],
            onChanged: (v) {
              final preset = v == null ? null : presetByName(v);
              // 选"自定义"不覆盖任何字段:地址与模型由用户自己填。
              if (preset == null) return;
              setState(() => _draft = _draft.withPreset(preset));
            },
          ),
          const SizedBox(height: 12),
          TextFieldSetting(
            key: const ValueKey('llmBaseUrlField'),
            label: l10n.llmBaseUrl,
            initial: _draft.baseUrl,
            onChanged: (v) =>
                setState(() => _draft = _draft.copyWith(baseUrl: v)),
          ),
          TextFieldSetting(
            key: const ValueKey('llmApiKeyField'),
            label: l10n.llmApiKey,
            initial: _draft.apiKey,
            obscure: true,
            onChanged: (v) => setState(() => _draft = _draft.copyWith(apiKey: v)),
          ),
          TextFieldSetting(
            key: const ValueKey('llmModelField'),
            label: l10n.llmModel,
            initial: _draft.model,
            onChanged: (v) => setState(() => _draft = _draft.copyWith(model: v)),
          ),
          TextFieldSetting(
            key: const ValueKey('llmSystemPromptField'),
            label: l10n.llmSystemPrompt,
            initial: _draft.systemPrompt,
            minLines: 4,
            maxLines: 8,
            onChanged: (v) =>
                setState(() => _draft = _draft.copyWith(systemPrompt: v)),
          ),
          Text(l10n.llmSystemPromptHint, style: AppText.caption),
          const SizedBox(height: 24),
          if (!_isNew) ...[
            Text(
              l10n.llmKeepOneConfig,
              style: AppText.caption,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('deleteLlmConfigButton'),
              onPressed: canDelete ? _delete : null,
              icon: const Icon(Icons.delete_outline),
              label: Text(l10n.llmDeleteConfig),
            ),
          ],
        ],
      ),
    );
  }
}
