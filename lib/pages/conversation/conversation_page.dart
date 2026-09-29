/// 对话页:初始化卡片(未就绪)→ 音频/文本双模式对话视图。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tts_demo/l10n/app_localizations.dart';
import 'package:flutter_tts_demo/pages/history/history_page.dart';
import 'package:flutter_tts_demo/utils/conversation_service.dart';

import 'components/mode_toggle.dart';
import 'conversation_mode.dart';
import 'sections/conversation_view.dart';
import 'sections/init_card.dart';

export 'conversation_mode.dart';

class ConversationPage extends StatefulWidget {
  const ConversationPage({super.key, this.onNavigateToSettings});

  /// 跳转到设置 Tab 的回调(由 MainShell 提供)。
  final VoidCallback? onNavigateToSettings;

  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  bool _downloading = false;
  double _progress = 0;
  ConversationMode _mode = ConversationMode.audio;

  Future<void> _downloadModels(ConversationService service) async {
    setState(() {
      _downloading = true;
      _progress = 0;
    });
    try {
      await service.downloadInitialModels((p) {
        if (mounted) setState(() => _progress = p);
      });
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<ConversationService>();
    final l10n = AppLocalizations.of(context);

    // 服务层拿不到 l10n,门禁的拒绝语由这里按当前语言注入。
    service.voiceprintGateReply = l10n.voiceprintGateRejected;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const ValueKey('historyButton'),
          tooltip: l10n.conversationHistory,
          icon: const Icon(Icons.history),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const HistoryPage()),
          ),
        ),
        title: ModeToggle(
          mode: _mode,
          onChanged: (m) => _onModeChanged(m, service),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            key: const ValueKey('conversationSettingsButton'),
            tooltip: l10n.settingsTab,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => widget.onNavigateToSettings?.call(),
          ),
        ],
      ),
      body: service.isReadyForConversation
          ? ConversationView(service: service, mode: _mode)
          : InitCard(
              downloading: _downloading,
              progress: _progress,
              onDownload: () => _downloadModels(service),
            ),
    );
  }

  void _onModeChanged(ConversationMode m, ConversationService service) {
    setState(() => _mode = m);
    if (m == ConversationMode.text) {
      service.stop(); // 切文本模式时停麦克风。
    }
  }
}
