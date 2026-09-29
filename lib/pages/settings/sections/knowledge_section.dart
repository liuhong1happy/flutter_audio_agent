/// 知识库设置段:开关 + 注入条数 + 相似度阈值 + 嵌入模型下载 + 管理入口。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tts_demo/components/theme/app_text.dart';
import 'package:flutter_tts_demo/data/models/tts_model.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';
import 'package:flutter_tts_demo/pages/knowledge/knowledge_page.dart';

import '../components/settings_widgets.dart';

class KnowledgeSection extends StatelessWidget {
  const KnowledgeSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<TtsSettings>();
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.sectionKnowledge)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader(l10n.sectionKnowledge, Icons.menu_book_outlined),
          SwitchListTile(
            key: const ValueKey('kbEnabledSwitch'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.kbEnabledLabel, style: AppText.body),
            subtitle: Text(l10n.kbEnabledHint, style: AppText.caption),
            value: settings.kbEnabled,
            onChanged: settings.setKbEnabled,
          ),
          const SectionDivider(),
          SettingLabel(l10n.kbTopKLabel),
          Slider(
            key: const ValueKey('kbTopKSlider'),
            value: settings.kbTopK.toDouble(),
            min: 1,
            max: 8,
            divisions: 7,
            label: '${settings.kbTopK}',
            onChanged: (v) => settings.setKbTopK(v.round()),
          ),
          SettingLabel(l10n.kbScoreThresholdLabel),
          Slider(
            key: const ValueKey('kbScoreThresholdSlider'),
            value: settings.kbScoreThreshold,
            min: 0.2,
            max: 0.8,
            divisions: 12,
            label: settings.kbScoreThreshold.toStringAsFixed(2),
            onChanged: settings.setKbScoreThreshold,
          ),
          // 阈值含义必须写出来:实测同义/异义的分数区间是用户唯一能判断
          // "该往哪调"的依据。
          Text(l10n.kbScoreThresholdHint, style: AppText.caption),
          const SectionDivider(),
          ManageEntry(
            // 本页有三处 "Knowledge base"(标题栏 / SectionHeader / 这个入口),
            // 只按文案定位不到入口,故显式给 key(端到端测试用)。
            key: const ValueKey('kbManageEntry'),
            icon: Icons.folder_open_outlined,
            title: l10n.kbManageTitle,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const KnowledgePage()),
            ),
          ),
          const SectionDivider(),
          SectionHeader(l10n.modelDownloadLabel, Icons.cloud_download_outlined),
          Text(l10n.kbEmbeddingModelLabel, style: AppText.caption),
          const SizedBox(height: 8),
          // 嵌入模型走通用下载列表(kind == embedding),与其它模型一致。
          const ModelDownloadList(kind: ModelKind.embedding),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
