/// 声纹识别设置段:阈值 + 注册说话人 + 声纹管理 + 模型下载。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tts_demo/data/models/tts_model.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';
import 'package:flutter_tts_demo/pages/voiceprint/voiceprint_page.dart';

import '../components/settings_widgets.dart';

class VoiceprintSection extends StatelessWidget {
  const VoiceprintSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<TtsSettings>();
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.sectionVoiceprint)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader(l10n.sectionVoiceprint, Icons.fingerprint),
          SettingLabel(l10n.voiceprintThreshold),
          Slider(
            key: const ValueKey('voiceprintThresholdSlider'),
            value: settings.voiceprintThreshold,
            min: 0.3,
            max: 0.9,
            divisions: 12,
            label: settings.voiceprintThreshold.toStringAsFixed(2),
            onChanged: (v) => settings.setVoiceprintThreshold(v),
          ),
          FilledButton.tonalIcon(
            key: const ValueKey('enrollSpeakerButton'),
            icon: const Icon(Icons.person_add_alt),
            label: Text(l10n.enrollSpeaker),
            onPressed: () => openEnrollSpeakerPage(context),
          ),
          const SizedBox(height: 8),
          ManageEntry(
            icon: Icons.person_outline,
            title: l10n.voiceprintTitle,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const VoiceprintPage()),
            ),
          ),
          const SectionDivider(),
          SectionHeader(l10n.modelDownloadLabel, Icons.cloud_download_outlined),
          const ModelDownloadList(kind: ModelKind.speaker),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
