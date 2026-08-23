/// 声纹管理页:列表 + 注册 + 测试识别 + 删除。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tts_demo/components/theme/app_text.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';
import 'package:flutter_tts_demo/utils/voiceprint_service.dart';

import 'components/identify_sheet.dart';
import 'sections/enroll_page.dart';

export 'sections/enroll_page.dart' show EnrollSpeakerPage;

/// 打开"注册说话人"页面(供声纹页与设置页复用)。
void openEnrollSpeakerPage(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => const EnrollSpeakerPage()),
  );
}

class VoiceprintPage extends StatelessWidget {
  const VoiceprintPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.watch<VoiceprintService>();
    final l10n = AppLocalizations.of(context);

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
      body: service.profiles.isEmpty
          ? Center(child: Text(l10n.noSpeakers, style: AppText.caption))
          : ListView.separated(
              itemCount: service.profiles.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final profile = service.profiles[i];
                return ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(profile.name),
                  subtitle: profile.note.isEmpty
                      ? null
                      : Text(profile.note, style: AppText.caption),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => service.remove(profile.name),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => openEnrollSpeakerPage(context),
        child: const Icon(Icons.person_add_alt),
      ),
    );
  }
}
