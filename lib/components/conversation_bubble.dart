/// 对话气泡(带说话人徽章 + 时间戳),供对话页与历史页复用。
library;

import 'package:flutter/material.dart';

import 'package:flutter_tts_demo/data/models/conversation_message.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';
import 'package:flutter_tts_demo/components/theme/app_colors.dart';
import 'package:flutter_tts_demo/components/theme/app_text.dart';

/// 毫秒时间戳 → HH:mm。
String formatConversationTime(int millis) {
  final t = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class ConversationBubble extends StatelessWidget {
  const ConversationBubble({super.key, required this.message, this.onLongPress});

  final ConversationMessage message;

  /// 长按回调(用于删除单条消息);为空则不可长按。
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isUser = message.role == ConversationRole.user;
    final badge = message.speakerName ?? l10n.speakerUnknown;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: const BoxConstraints(maxWidth: 320),
          decoration: BoxDecoration(
            color: isUser ? AppColors.accentWeak : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isUser)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    badge,
                    style: AppText.caption.copyWith(color: AppColors.inkTertiary),
                  ),
                ),
              Text(message.content, style: AppText.body),
              const SizedBox(height: 2),
              Text(
                formatConversationTime(message.createdAt),
                style: AppText.caption.copyWith(
                  color: AppColors.inkDisabled,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
