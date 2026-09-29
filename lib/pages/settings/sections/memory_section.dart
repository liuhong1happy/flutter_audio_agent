/// 记忆设置段:长期记忆开关 + 抽取频率 + 注入条数 + 管理入口。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tts_demo/components/theme/app_text.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';
import 'package:flutter_tts_demo/pages/memory/memory_page.dart';

import '../components/settings_widgets.dart';

class MemorySection extends StatelessWidget {
  const MemorySection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<TtsSettings>();
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.sectionMemory)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader(l10n.sectionMemory, Icons.psychology_outlined),
          SwitchListTile(
            key: const ValueKey('memoryEnabledSwitch'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.memoryEnabledLabel, style: AppText.body),
            // 必须说明会花 token:用户自付 API 费用,不能悄悄替他决定。
            subtitle: Text(l10n.memoryEnabledHint, style: AppText.caption),
            value: settings.memoryEnabled,
            onChanged: settings.setMemoryEnabled,
          ),
          const SectionDivider(),
          SettingLabel(l10n.memoryExtractIntervalLabel),
          Slider(
            key: const ValueKey('memoryIntervalSlider'),
            value: settings.memoryExtractInterval.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            label: '${settings.memoryExtractInterval}',
            onChanged: (v) => settings.setMemoryExtractInterval(v.round()),
          ),
          SettingLabel(l10n.memoryTopKLabel),
          Slider(
            key: const ValueKey('memoryTopKSlider'),
            value: settings.memoryTopK.toDouble(),
            min: 1,
            max: 12,
            divisions: 11,
            label: '${settings.memoryTopK}',
            onChanged: (v) => settings.setMemoryTopK(v.round()),
          ),
          const SectionDivider(),
          ManageEntry(
            // 本页有三处 "Memory"(标题栏 / SectionHeader / 这个入口),
            // 只按文案定位不到入口,故显式给 key(端到端测试用)。
            key: const ValueKey('memoryManageEntry'),
            icon: Icons.psychology_alt_outlined,
            title: l10n.memoryManageTitle,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const MemoryPage()),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
