/// 语音合成 (TTS) 设置段:模型选择 + 参数 + 模型下载 + 克隆音入口。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tts_demo/components/theme/app_colors.dart';
import 'package:flutter_tts_demo/components/theme/app_text.dart';
import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/data/model_manager.dart';
import 'package:flutter_tts_demo/data/models/tts_model.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';
import 'package:flutter_tts_demo/pages/clone_voices/clone_voices_page.dart';

import '../components/settings_widgets.dart';

class TtsVoiceSection extends StatelessWidget {
  const TtsVoiceSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<TtsSettings>();
    final manager = context.watch<ModelManager>();
    final l10n = AppLocalizations.of(context);

    final downloadedModels = ModelCatalog.all
        .where((m) => m.kind == ModelKind.tts && manager.isDownloaded(m.id))
        .toList();
    final selectedModel = ModelCatalog.byId(settings.selectedModelId);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.sectionTts)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader(l10n.selectModelLabel, Icons.record_voice_over_outlined),
          if (downloadedModels.isEmpty)
            Text(l10n.noModelDownloaded,
                style: AppText.caption.copyWith(color: AppColors.danger))
          else
            DropdownButtonFormField<String>(
              key: const ValueKey('modelSelector'),
              initialValue: selectedModel?.id,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
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
          if (selectedModel != null && selectedModel.speakers > 1) ...[
            const SizedBox(height: 16),
            SettingLabel(l10n.speakerLabel(settings.sid)),
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
          const SizedBox(height: 8),
          SettingLabel(l10n.speedLabel(settings.speed.toStringAsFixed(2))),
          Slider(
            key: const ValueKey('speedSlider'),
            value: settings.speed,
            min: 0.5,
            max: 2.0,
            divisions: 30,
            label: '${settings.speed.toStringAsFixed(2)}x',
            onChanged: (v) => settings.setSpeed(v),
          ),
          SettingLabel(l10n.silenceLabel((settings.silenceScale * 100).round())),
          Slider(
            key: const ValueKey('silenceSlider'),
            value: settings.silenceScale,
            min: 0,
            max: 1.0,
            divisions: 20,
            onChanged: (v) => settings.setSilenceScale(v),
          ),
          SettingLabel(l10n.threadLabel(settings.numThreads)),
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

          const SectionDivider(),
          SectionHeader(l10n.modelDownloadLabel, Icons.cloud_download_outlined),
          const ModelDownloadList(kind: ModelKind.tts),

          const SectionDivider(),
          ManageEntry(
            icon: Icons.record_voice_over_outlined,
            title: l10n.cloneVoicesTitle,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const CloneVoicesPage()),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
