/// 语音识别 (ASR) 设置段:模型选择 + 模型下载。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/data/models/tts_model.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';

import '../components/settings_widgets.dart';

class AsrSection extends StatelessWidget {
  const AsrSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<TtsSettings>();
    final l10n = AppLocalizations.of(context);
    final asrModels = ModelCatalog.all
        .where((m) =>
            m.kind == ModelKind.asrParaformer ||
            m.kind == ModelKind.asrSenseVoice)
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.sectionAsr)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader(l10n.asrModelLabel, Icons.hearing_outlined),
          DropdownButtonFormField<String>(
            key: const ValueKey('asrModelSelector'),
            initialValue: settings.asrModelId,
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: [
              for (final m in asrModels)
                DropdownMenuItem(value: m.id, child: Text(m.displayName)),
            ],
            onChanged: (id) => settings.setAsrModelId(id),
          ),
          const SectionDivider(),
          SectionHeader(l10n.modelDownloadLabel, Icons.cloud_download_outlined),
          const ModelDownloadList(kind: ModelKind.asrParaformer),
          const ModelDownloadList(kind: ModelKind.asrSenseVoice),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
