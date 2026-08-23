/// 声音选择:模型音色 + 克隆音。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tts_demo/components/theme/app_text.dart';
import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/data/model_manager.dart';
import 'package:flutter_tts_demo/data/models/tts_model.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';
import 'package:flutter_tts_demo/utils/voice_cloning_service.dart';

class VoiceSelector extends StatelessWidget {
  const VoiceSelector({super.key, required this.settings});

  final TtsSettings settings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return IconButton(
      tooltip: l10n.voiceSelectLabel,
      icon: const Icon(Icons.record_voice_over_outlined),
      onPressed: () => _showSheet(context),
    );
  }

  void _showSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final manager = context.read<ModelManager>();
    final cloning = context.read<VoiceCloningService>();
    final models = ModelCatalog.all
        .where((m) => m.kind == ModelKind.tts && manager.isDownloaded(m.id))
        .toList();

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text(l10n.voiceModelLabel, style: AppText.headline)),
            for (final m in models)
              ListTile(
                leading: const Icon(Icons.record_voice_over_outlined),
                title: Text(m.displayName),
                onTap: () {
                  settings.setConversationVoiceModel(m.id, 0);
                  Navigator.pop(ctx);
                },
              ),
            ListTile(title: Text(l10n.voiceCloneLabel, style: AppText.headline)),
            for (final p in cloning.profiles)
              ListTile(
                leading: const Icon(Icons.person),
                title: Text(p.name),
                onTap: () {
                  settings.setConversationVoiceClone(p.id);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }
}
