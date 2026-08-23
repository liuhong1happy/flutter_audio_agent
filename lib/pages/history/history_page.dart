/// 历史会话浏览页:单一时间线、按时间排序、向前翻页(加载更早)、
/// 长按删除单条消息。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tts_demo/data/models/conversation_message.dart';
import 'package:flutter_tts_demo/utils/conversation_service.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';
import 'package:flutter_tts_demo/components/theme/app_colors.dart';
import 'package:flutter_tts_demo/components/theme/app_text.dart';
import 'package:flutter_tts_demo/components/conversation_bubble.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  Future<void> _confirmDelete(ConversationMessage m) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.delete),
        content: Text(l10n.deleteMessageConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final id = m.id;
      if (id != null) {
        await context.read<ConversationService>().deleteMessage(id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ConversationService>();
    final l10n = AppLocalizations.of(context);
    final messages = service.messages;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.conversationHistory)),
      body: messages.isEmpty
          ? Center(
              child: Text(
                l10n.historyEmpty,
                style: AppText.caption.copyWith(color: AppColors.inkTertiary),
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                if (service.hasMore)
                  Center(
                    child: TextButton.icon(
                      key: const ValueKey('loadOlderButton'),
                      onPressed: () => service.loadOlder(),
                      icon: const Icon(Icons.expand_less, size: 18),
                      label: Text(l10n.loadOlder),
                    ),
                  ),
                for (final m in messages)
                  ConversationBubble(
                    message: m,
                    onLongPress: () => _confirmDelete(m),
                  ),
              ],
            ),
    );
  }
}
