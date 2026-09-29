/// 设置 Tab:大类列表 → 点击进入各自子页。
library;

import 'package:flutter/material.dart';

import 'package:flutter_tts_demo/l10n/app_localizations.dart';

import 'components/settings_widgets.dart';
import 'sections/asr_section.dart';
import 'sections/general_section.dart';
import 'sections/knowledge_section.dart';
import 'sections/llm_section.dart';
import 'sections/memory_section.dart';
import 'sections/tts_section.dart';
import 'sections/vad_section.dart';
import 'sections/voiceprint_section.dart';

class TtsSettingsPage extends StatelessWidget {
  const TtsSettingsPage({super.key});

  void _push(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: [
          CategoryTile(
            icon: Icons.record_voice_over_outlined,
            title: l10n.sectionTts,
            onTap: () => _push(context, const TtsVoiceSection()),
          ),
          CategoryTile(
            icon: Icons.hearing_outlined,
            title: l10n.sectionAsr,
            onTap: () => _push(context, const AsrSection()),
          ),
          CategoryTile(
            icon: Icons.sensors_outlined,
            title: l10n.sectionVad,
            onTap: () => _push(context, const VadSection()),
          ),
          CategoryTile(
            icon: Icons.fingerprint,
            title: l10n.sectionVoiceprint,
            onTap: () => _push(context, const VoiceprintSection()),
          ),
          CategoryTile(
            icon: Icons.menu_book_outlined,
            title: l10n.sectionKnowledge,
            onTap: () => _push(context, const KnowledgeSection()),
          ),
          CategoryTile(
            icon: Icons.psychology_outlined,
            title: l10n.sectionMemory,
            onTap: () => _push(context, const MemorySection()),
          ),
          CategoryTile(
            icon: Icons.smart_toy_outlined,
            title: l10n.sectionLlm,
            onTap: () => _push(context, const LlmSection()),
          ),
          CategoryTile(
            icon: Icons.settings_outlined,
            title: l10n.sectionGeneral,
            onTap: () => _push(context, const GeneralSection()),
          ),
        ],
      ),
    );
  }
}
