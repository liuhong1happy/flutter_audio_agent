/// 大模型 (LLM) 设置段:服务商预设 + baseUrl / apiKey / 模型 / 提示词。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';

import '../components/settings_widgets.dart';

/// OpenAI 兼容服务商预设。
class LlmProviderPreset {
  const LlmProviderPreset({
    required this.name,
    required this.baseUrl,
    required this.model,
  });

  final String name;
  final String baseUrl;
  final String model;
}

const List<LlmProviderPreset> llmPresets = [
  LlmProviderPreset(
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    model: 'deepseek-v4-flash',
  ),
  LlmProviderPreset(
    name: 'Moonshot (Kimi)',
    baseUrl: 'https://api.moonshot.cn/v1',
    model: 'moonshot-v1-8k',
  ),
  LlmProviderPreset(
    name: '智谱 (GLM)',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    model: 'glm-4-flash',
  ),
  LlmProviderPreset(
    name: '通义千问 (Qwen)',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    model: 'qwen-plus',
  ),
];

const String kCustomProvider = 'custom';

class LlmSection extends StatelessWidget {
  const LlmSection({super.key});

  static String _currentProvider(String baseUrl) {
    for (final p in llmPresets) {
      if (p.baseUrl == baseUrl) return p.name;
    }
    return kCustomProvider;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<TtsSettings>();
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.sectionLlm)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader(l10n.sectionLlm, Icons.smart_toy_outlined),
          SettingLabel(l10n.llmProvider),
          DropdownButtonFormField<String>(
            initialValue: _currentProvider(settings.llmBaseUrl),
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
              for (final p in llmPresets) {
                if (p.name == v) {
                  settings.setLlmBaseUrl(p.baseUrl);
                  settings.setLlmModel(p.model);
                  return;
                }
              }
            },
          ),
          const SizedBox(height: 12),
          TextFieldSetting(
            label: l10n.llmBaseUrl,
            initial: settings.llmBaseUrl,
            onChanged: (v) => settings.setLlmBaseUrl(v.trim()),
          ),
          TextFieldSetting(
            label: l10n.llmApiKey,
            initial: settings.llmApiKey,
            obscure: true,
            onChanged: (v) => settings.setLlmApiKey(v.trim()),
          ),
          TextFieldSetting(
            label: l10n.llmModel,
            initial: settings.llmModel,
            onChanged: (v) => settings.setLlmModel(v.trim()),
          ),
          TextFieldSetting(
            label: l10n.llmSystemPrompt,
            initial: settings.llmSystemPrompt,
            maxLines: 3,
            onChanged: (v) => settings.setLlmSystemPrompt(v),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
