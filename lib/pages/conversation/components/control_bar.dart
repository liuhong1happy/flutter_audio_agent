/// 底部控制栏:清空历史 + 开始/停止对话(音频模式)。
library;

import 'package:flutter/material.dart';

import 'package:flutter_tts_demo/components/theme/app_colors.dart';
import 'package:flutter_tts_demo/components/theme/app_spacing.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';
import 'package:flutter_tts_demo/utils/conversation_service.dart';

class ControlBar extends StatelessWidget {
  const ControlBar({super.key, required this.service});

  final ConversationService service;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final active = service.phase != ConversationPhase.idle &&
        service.phase != ConversationPhase.error;

    return Material(
      color: AppColors.bg,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              IconButton(
                tooltip: l10n.clearConversation,
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: () => service.clearHistory(),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('conversationToggleButton'),
                  onPressed: active ? () => service.stop() : () => service.start(),
                  icon: Icon(active ? Icons.stop : Icons.play_arrow),
                  label: Text(active ? l10n.stopConversation : l10n.startConversation),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
