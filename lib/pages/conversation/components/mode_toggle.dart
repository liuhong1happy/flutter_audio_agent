/// 音频 / 文本模式切换。
library;

import 'package:flutter/material.dart';

import 'package:flutter_tts_demo/l10n/app_localizations.dart';

import '../conversation_mode.dart';

class ModeToggle extends StatelessWidget {
  const ModeToggle({super.key, required this.mode, required this.onChanged});

  final ConversationMode mode;
  final ValueChanged<ConversationMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SegmentedButton<ConversationMode>(
      segments: [
        ButtonSegment(
          value: ConversationMode.audio,
          label: Text(l10n.audioMode),
          icon: const Icon(Icons.mic_none, size: 16),
        ),
        ButtonSegment(
          value: ConversationMode.text,
          label: Text(l10n.textMode),
          icon: const Icon(Icons.chat_outlined, size: 16),
        ),
      ],
      selected: {mode},
      onSelectionChanged: (s) => onChanged(s.first),
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
