/// 大模型 (LLM) 设置:已配置的大模型列表(启用一条)+ 增删改。
///
/// 旧版是单组 地址/Key/模型/提示词,换服务商就把上一家覆盖掉。现在改成
/// **可逐条添加的配置列表**,其中一条启用为默认;实际请求只走启用那条。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tts_demo/components/theme/app_colors.dart';
import 'package:flutter_tts_demo/components/theme/app_text.dart';
import 'package:flutter_tts_demo/data/models/llm_config.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';

import '../components/settings_widgets.dart';
import 'llm_config_edit_page.dart';

class LlmSection extends StatelessWidget {
  const LlmSection({super.key});

  void _openEditor(BuildContext context, LlmConfig? config) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => LlmConfigEditPage(initial: config),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<TtsSettings>();
    final l10n = AppLocalizations.of(context);
    final configs = settings.llmConfigs;
    final activeId = settings.activeLlmConfigId;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.sectionLlm)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader(l10n.llmConfigListTitle, Icons.smart_toy_outlined),
          for (final c in configs)
            ListTile(
              key: ValueKey('llmConfigRow_${c.id}'),
              contentPadding: EdgeInsets.zero,
              leading: IconButton(
                key: ValueKey('llmConfigRadio_${c.id}'),
                tooltip: l10n.llmSetActive,
                icon: Icon(
                  c.id == activeId
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: c.id == activeId
                      ? AppColors.accent
                      : AppColors.inkTertiary,
                ),
                onPressed: () => settings.setActiveLlmConfig(c.id),
              ),
              title: Text(c.name, style: AppText.body),
              subtitle: Text(
                c.isConfigured
                    ? c.subtitle
                    : '${c.subtitle} · ${l10n.llmConfigIncomplete}',
                style: AppText.caption.copyWith(
                  color: c.isConfigured ? null : AppColors.danger,
                ),
              ),
              trailing: c.id == activeId
                  ? Text(l10n.llmConfigActive, style: AppText.caption)
                  : const Icon(Icons.chevron_right),
              onTap: () => _openEditor(context, c),
            ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            key: const ValueKey('llmAddConfigButton'),
            icon: const Icon(Icons.add),
            label: Text(l10n.llmAddConfig),
            onPressed: () => _openEditor(context, null),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
