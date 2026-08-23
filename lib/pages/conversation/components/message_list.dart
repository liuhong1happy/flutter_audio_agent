/// 消息列表:音频模式仅显示最后一轮,文本模式显示全部;支持加载更早 + 长按删除。
library;

import 'package:flutter/material.dart';

import 'package:flutter_tts_demo/components/conversation_bubble.dart';
import 'package:flutter_tts_demo/components/theme/app_colors.dart';
import 'package:flutter_tts_demo/components/theme/app_text.dart';
import 'package:flutter_tts_demo/data/models/conversation_message.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';
import 'package:flutter_tts_demo/utils/conversation_service.dart';

import '../conversation_mode.dart';

class MessageList extends StatefulWidget {
  const MessageList({super.key, required this.service, required this.mode});

  final ConversationService service;
  final ConversationMode mode;

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  final ScrollController _controller = ScrollController();
  String? _lastSignature;

  /// 音频模式:取最后一轮(最后一个用户消息到末尾,含其后助手回复)。
  static List<ConversationMessage> _lastRound(List<ConversationMessage> all) {
    for (var i = all.length - 1; i >= 0; i--) {
      if (all[i].role == ConversationRole.user) return all.sublist(i);
    }
    return all;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 新消息追加(或流式文本变化)时滚动到底部;向前翻页(loadOlder)不触发。
  void _maybeScrollToBottom() {
    final messages = widget.service.messages;
    final signature = '${messages.isEmpty ? '' : messages.last.content}'
        '|${widget.service.streamingText}';
    if (signature == _lastSignature) return;
    final isFirst = _lastSignature == null;
    _lastSignature = signature;
    if (isFirst) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller.hasClients) {
        _controller.animateTo(
          _controller.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

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
      if (id != null) await widget.service.deleteMessage(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    _maybeScrollToBottom();
    final l10n = AppLocalizations.of(context);
    final allMessages = widget.service.messages;
    // 音频模式仅展示最后一轮,文本模式展示全部。
    final messages = widget.mode == ConversationMode.audio
        ? _lastRound(allMessages)
        : allMessages;

    if (messages.isEmpty && widget.service.streamingText.isEmpty) {
      return Center(
        child: Text(l10n.initReady,
            style: AppText.caption.copyWith(color: AppColors.inkTertiary)),
      );
    }

    final children = <Widget>[
      if (widget.service.hasMore)
        Center(
          child: TextButton.icon(
            onPressed: () => widget.service.loadOlder(),
            icon: const Icon(Icons.expand_less, size: 18),
            label: Text(l10n.loadOlder),
          ),
        ),
      for (final m in messages)
        ConversationBubble(
          message: m,
          onLongPress: m.id == null ? null : () => _confirmDelete(m),
        ),
      if (widget.service.streamingText.isNotEmpty)
        ConversationBubble(
          message: ConversationMessage(
            role: ConversationRole.assistant,
            content: widget.service.streamingText,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        ),
    ];

    return ListView(
      controller: _controller,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: children,
    );
  }
}
