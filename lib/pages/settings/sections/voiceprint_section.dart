/// 声纹识别设置段:当前模型 + 阈值 + 门禁 + 认证保护 + 注册/管理 + 模型下载。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tts_demo/components/theme/app_text.dart';
import 'package:flutter_tts_demo/data/app_dependencies.dart';
import 'package:flutter_tts_demo/data/models/tts_model.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';
import 'package:flutter_tts_demo/pages/voiceprint/utils/voiceprint_auth.dart';
import 'package:flutter_tts_demo/pages/voiceprint/voiceprint_page.dart';
import 'package:flutter_tts_demo/utils/voiceprint_service.dart';

import '../components/settings_widgets.dart';

class VoiceprintSection extends StatelessWidget {
  const VoiceprintSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<TtsSettings>();
    final service = context.watch<VoiceprintService>();
    final l10n = AppLocalizations.of(context);
    final currentName = service.displayNameOf(service.currentModelId);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.sectionVoiceprint)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader(l10n.sectionVoiceprint, Icons.fingerprint),
          // 阈值是按当前模型的嵌入分布调的,把这行紧贴滑块,免得换模型后
          // 用户不知道阈值作用在谁身上。
          if (currentName != null) ...[
            Text(
              l10n.currentVoiceprintModel(currentName),
              key: const ValueKey('settingsVoiceprintModelLabel'),
              style: AppText.caption,
            ),
            const SizedBox(height: 8),
          ],
          SettingLabel(l10n.voiceprintThreshold),
          Slider(
            key: const ValueKey('voiceprintThresholdSlider'),
            value: settings.voiceprintThreshold,
            min: 0.3,
            max: 0.9,
            divisions: 12,
            label: settings.voiceprintThreshold.toStringAsFixed(2),
            // 拖动是高频操作,所以用会话式认证(ensureUnlocked):认证一次,
            // 有效期内随便拖,而不是每动一格弹一次指纹。
            onChangeStart: (_) => unawaited(ensureVoiceprintAuth(context)),
            // 光弹认证不拦写入等于没守:认证没通过就不落值,滑块会弹回原位。
            onChanged: (v) {
              final lock = context.read<AppDependencies>().appLock;
              if (settings.requireAuthForEnroll && !lock.isUnlocked) return;
              settings.setVoiceprintThreshold(v);
            },
          ),
          const SectionDivider(),
          SwitchListTile(
            key: const ValueKey('voiceprintGateSwitch'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.voiceprintGateLabel, style: AppText.body),
            value: settings.voiceprintGateEnabled,
            onChanged: settings.setVoiceprintGateEnabled,
          ),
          SwitchListTile(
            key: const ValueKey('requireAuthForEnrollSwitch'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.requireAuthForEnroll, style: AppText.body),
            value: settings.requireAuthForEnroll,
            onChanged: settings.setRequireAuthForEnroll,
          ),
          const SectionDivider(),
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
