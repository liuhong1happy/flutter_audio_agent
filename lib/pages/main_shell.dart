/// 底部 Tab 主骨架。
///
/// 三个平级 Tab:合成 / 对话 / 设置。用 [IndexedStack] 常驻各页,
/// 切换 Tab 不销毁状态——正在播放的音频不会被打断。
/// 模型下载已并入设置页各分类子页,故不再有独立的"模型"Tab。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tts_demo/data/model_manager.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';
import 'package:flutter_tts_demo/pages/conversation/conversation_page.dart';
import 'package:flutter_tts_demo/pages/synthesize/synthesize_page.dart';
import 'package:flutter_tts_demo/pages/settings/tts_settings_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  void _switchTo(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<ModelManager>();
    final l10n = AppLocalizations.of(context);
    final hasDownloads = manager.hasActiveDownloads;

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          SynthesizePage(onNavigateToSettings: () => _switchTo(2)),
          ConversationPage(onNavigateToSettings: () => _switchTo(2)),
          const TtsSettingsPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _switchTo,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.graphic_eq_outlined),
            selectedIcon: const Icon(Icons.graphic_eq),
            label: l10n.synthesizeTab,
          ),
          NavigationDestination(
            key: const ValueKey('tabConversation'),
            icon: const Icon(Icons.chat_bubble_outline),
            selectedIcon: const Icon(Icons.chat_bubble),
            label: l10n.conversationTab,
          ),
          NavigationDestination(
            key: const ValueKey('tabSettings'),
            icon: hasDownloads
                ? Badge(
                    smallSize: 8,
                    child: const Icon(Icons.settings_outlined),
                  )
                : const Icon(Icons.settings_outlined),
            selectedIcon: hasDownloads
                ? Badge(
                    smallSize: 8,
                    child: const Icon(Icons.settings),
                  )
                : const Icon(Icons.settings),
            label: l10n.settingsTab,
          ),
        ],
      ),
    );
  }
}
