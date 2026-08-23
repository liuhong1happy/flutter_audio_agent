/// 语音活动检测 (VAD) 设置段:阈值 / 静音时长 + 模型下载。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tts_demo/data/models/tts_model.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';

import '../components/settings_widgets.dart';

class VadSection extends StatelessWidget {
  const VadSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<TtsSettings>();
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.sectionVad)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader(l10n.sectionVad, Icons.sensors_outlined),
          SettingLabel(l10n.vadThreshold),
          Slider(
            key: const ValueKey('vadThresholdSlider'),
            value: settings.vadThreshold,
            min: 0.1,
            max: 0.9,
            divisions: 8,
            label: settings.vadThreshold.toStringAsFixed(2),
            onChanged: (v) => settings.setVadThreshold(v),
          ),
          SettingLabel(l10n.vadMinSilence),
          Slider(
            key: const ValueKey('vadMinSilenceSlider'),
            value: settings.vadMinSilence,
            min: 0.2,
            max: 2.0,
            divisions: 18,
            label: settings.vadMinSilence.toStringAsFixed(1),
            onChanged: (v) => settings.setVadMinSilence(v),
          ),
          const SectionDivider(),
          SectionHeader(l10n.modelDownloadLabel, Icons.cloud_download_outlined),
          const ModelDownloadList(kind: ModelKind.vad),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
