/// 底部 Tab 主骨架(需求:使用底部 Tab 优化 UI)。
///
/// 三个平级 Tab:合成 / 模型 / 设置。用 [IndexedStack] 常驻各页,
/// 切换 Tab 不销毁状态——正在播放的音频不会被打断。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/model_manager.dart';
import 'model_manage_page.dart';
import 'synthesize_page.dart';
import 'tts_settings_page.dart';

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
    final hasDownloads = manager.hasActiveDownloads;

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          SynthesizePage(onNavigateToSettings: () => _switchTo(2)),
          const ModelManagePage(),
          TtsSettingsPage(onNavigateToModel: () => _switchTo(1)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _switchTo,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.graphic_eq_outlined),
            selectedIcon: Icon(Icons.graphic_eq),
            label: '合成',
          ),
          NavigationDestination(
            key: const ValueKey('tabModel'),
            icon: hasDownloads
                ? Badge(
                    smallSize: 8,
                    child: const Icon(Icons.download_for_offline_outlined),
                  )
                : const Icon(Icons.download_for_offline_outlined),
            selectedIcon: hasDownloads
                ? Badge(
                    smallSize: 8,
                    child: const Icon(Icons.download_for_offline),
                  )
                : const Icon(Icons.download_for_offline),
            label: '模型',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
