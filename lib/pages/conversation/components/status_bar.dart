/// 状态栏:阶段胶囊 + 说话人胶囊 + 静音 + 声音选择。
library;

import 'package:flutter/material.dart';

import 'package:flutter_tts_demo/components/theme/app_colors.dart';
import 'package:flutter_tts_demo/components/theme/app_spacing.dart';
import 'package:flutter_tts_demo/components/theme/app_text.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';
import 'package:flutter_tts_demo/utils/conversation_service.dart';

import 'voice_selector.dart';

class StatusBar extends StatelessWidget {
  const StatusBar({super.key, required this.service, required this.settings});

  final ConversationService service;
  final TtsSettings settings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final speaker = service.currentSpeaker;
    final phaseColor = switch (service.phase) {
      ConversationPhase.listening => AppColors.success,
      ConversationPhase.error => AppColors.danger,
      _ => AppColors.accent,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Chip(
            avatar: Icon(Icons.graphic_eq, size: 16, color: phaseColor),
            label: Text(_phaseText(context, service),
                style: AppText.caption.copyWith(color: phaseColor)),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: AppSpacing.sm),
          Chip(
            avatar: Icon(
              speaker == null ? Icons.person_off_outlined : Icons.person,
              size: 16,
            ),
            label: Text(
              speaker == null
                  ? '${l10n.speakerUnknown} · ${l10n.guestMode}'
                  : l10n.currentSpeaker(speaker),
              style: AppText.caption,
            ),
            visualDensity: VisualDensity.compact,
          ),
          const Spacer(),
          IconButton(
            tooltip: service.isMuted ? l10n.micUnmuted : l10n.micMuted,
            icon: Icon(service.isMuted ? Icons.mic_off : Icons.mic),
            onPressed: () => service.toggleMute(),
            visualDensity: VisualDensity.compact,
          ),
          VoiceSelector(settings: settings),
        ],
      ),
    );
  }

  static String _phaseText(BuildContext context, ConversationService service) {
    final l10n = AppLocalizations.of(context);
    return switch (service.phase) {
      ConversationPhase.idle => l10n.initReady,
      ConversationPhase.listening => l10n.listening,
      ConversationPhase.asr || ConversationPhase.identifying => l10n.recognizing,
      ConversationPhase.thinking => l10n.thinking,
      ConversationPhase.speaking => l10n.speaking,
      // error 阶段不只有 LLM 错误:声纹门禁 fail-closed 拒绝启动也落在这里,
      // 一律显示"LLM 错误"会把人引向错误的排查方向。
      ConversationPhase.error => service.lastError == 'voiceprintGateNoProfiles'
          ? l10n.voiceprintGateNoProfiles
          : l10n.llmError,
    };
  }
}
