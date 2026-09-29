/// 声纹管理页:当前模型 + 列表 + 注册 + 测试识别 + 删除 + 绑定克隆音。
///
/// 列表只显示**当前模型**的档案:不同声纹模型的嵌入空间互不通用,
/// 把两批人混在一张表里会让人误以为"注册了就该能认出来"。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tts_demo/components/theme/app_text.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';
import 'package:flutter_tts_demo/utils/voice_cloning_service.dart';
import 'package:flutter_tts_demo/utils/voiceprint_service.dart';

import 'components/identify_sheet.dart';
import 'sections/enroll_page.dart';
import 'utils/voiceprint_auth.dart';

export 'sections/enroll_page.dart' show EnrollSpeakerPage;

/// 打开"注册说话人"页面(供声纹页与设置页复用)。
void openEnrollSpeakerPage(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => const EnrollSpeakerPage()),
  );
}

/// 弹窗选择结果(null 表示什么都没选,即用户取消)。
class _CloneChoice {
  const _CloneChoice(this.cloneId);
  final String? cloneId;
}

class VoiceprintPage extends StatelessWidget {
  const VoiceprintPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<VoiceprintService>();
    final l10n = AppLocalizations.of(context);
    final models = service.downloadedSpeakerModels;
    final currentId = service.currentModelId;
    final currentName = service.displayNameOf(currentId);
    final others = service.modelIdsWithProfiles
        .where((id) => id != currentId)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.voiceprintTitle),
        actions: [
          IconButton(
            tooltip: l10n.identifyTest,
            icon: const Icon(Icons.search),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => const IdentifySheet(),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (models.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.noModelDownloaded, style: AppText.caption),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (currentName != null)
                    Text(
                      l10n.currentVoiceprintModel(currentName),
                      style: AppText.caption,
                    ),
                  if (models.length > 1) ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('voiceprintModelSelector'),
                      initialValue: currentId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l10n.voiceprintModelLabel,
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        for (final m in models)
                          DropdownMenuItem(
                            value: m.id,
                            child: Text(
                              m.displayName,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (id) {
                        if (id != null) {
                          context.read<TtsSettings>().setVoiceprintModelId(id);
                        }
                      },
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.voiceprintModelIsolationHint,
                      style: AppText.caption,
                    ),
                  ],
                  for (final id in others)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        l10n.otherVoiceprintModelHint(
                          service.countOf(id),
                          service.displayNameOf(id) ?? id,
                        ),
                        style: AppText.caption,
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: service.profiles.isEmpty
                ? Center(child: Text(l10n.noSpeakers, style: AppText.caption))
                : ListView.separated(
                    itemCount: service.profiles.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final profile = service.profiles[i];
                      return ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(profile.name),
                        subtitle: _subtitle(context, l10n, profile),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: l10n.bindCloneVoice,
                              icon: Icon(
                                profile.cloneId == null
                                    ? Icons.record_voice_over_outlined
                                    : Icons.record_voice_over,
                              ),
                              onPressed: () => _bindClone(context, profile.name),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                if (!await ensureVoiceprintAuth(context)) return;
                                await service.remove(profile.name);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => openEnrollSpeakerPage(context),
        child: const Icon(Icons.person_add_alt),
      ),
    );
  }

  Widget? _subtitle(
    BuildContext context,
    AppLocalizations l10n,
    VoiceprintProfile profile,
  ) {
    final cloning = context.watch<VoiceCloningService>();
    final boundName =
        profile.cloneId == null ? null : cloning.byId(profile.cloneId)?.name;
    final lines = <String>[
      if (profile.note.isNotEmpty) profile.note,
      if (boundName != null) l10n.cloneVoiceBound(boundName),
    ];
    if (lines.isEmpty) return null;
    return Text(lines.join(' · '), style: AppText.caption);
  }

  /// 给某位说话人挑一个克隆音(或解绑)。
  Future<void> _bindClone(BuildContext context, String name) async {
    final l10n = AppLocalizations.of(context);
    final service = context.read<VoiceprintService>();
    final cloning = context.read<VoiceCloningService>();
    final current = service.profileOf(name)?.cloneId;

    final choice = await showModalBottomSheet<_CloneChoice>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(l10n.bindCloneVoice, style: AppText.headline),
              subtitle: Text(l10n.bindCloneHint, style: AppText.caption),
            ),
            for (final p in cloning.profiles)
              ListTile(
                leading: Icon(
                  p.id == current ? Icons.check_circle : Icons.person,
                ),
                title: Text(p.name),
                onTap: () => Navigator.pop(ctx, _CloneChoice(p.id)),
              ),
            if (current != null)
              ListTile(
                leading: const Icon(Icons.link_off),
                title: Text(l10n.unbind),
                onTap: () => Navigator.pop(ctx, const _CloneChoice(null)),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    await service.bindClone(name, choice.cloneId);
  }
}
