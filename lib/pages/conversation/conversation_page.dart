/// 对话页:初始化卡片(未就绪)→ 音频/文本双模式对话视图。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';
import 'package:flutter_tts_demo/pages/history/history_page.dart';
import 'package:flutter_tts_demo/pages/settings/sections/llm_section.dart';
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
    // 必须同时 watch 设置:改大模型 API Key 走的是 TtsSettings.notifyListeners(),
    // 不会触发 ConversationService 通知 —— 不 watch 的话填完 Key 回来页面还卡在
    // 初始化卡片上出不去。
    final settings = context.watch<TtsSettings>();
    final l10n = AppLocalizations.of(context);

    // 服务层拿不到 l10n,门禁的拒绝语由这里按当前语言注入。
    service.voiceprintGateReply = l10n.voiceprintGateRejected;

    // 就绪判定按模式区分:文本模式只用 LLM,不需要任何本地模型。
    final ready = _mode == ConversationMode.text
        ? service.isReadyForTextMode
        : service.isReadyForAudioMode;

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
      body: ready
          ? ConversationView(service: service, mode: _mode)
          : InitCard(
              mode: _mode,
              modelsReady: service.isReadyForConversation,
              llmReady: settings.isLlmConfigured,
              downloading: _downloading,
              progress: _progress,
              onDownload: () => _downloadModels(service),
              // 直接 push LLM 设置页,比走"切到设置 Tab 再点进去"少两步。
              onConfigureLlm: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const LlmSection()),
              ),
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
