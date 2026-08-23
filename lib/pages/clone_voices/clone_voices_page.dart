/// 克隆音管理页:列表 + 新建(命名 → 录参考语音)+ 删除。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:flutter_tts_demo/data/app_dependencies.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';
import 'package:flutter_tts_demo/components/theme/app_text.dart';
import 'package:flutter_tts_demo/utils/voice_cloning_service.dart';

class CloneVoicesPage extends StatelessWidget {
  const CloneVoicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cloning = context.watch<VoiceCloningService>();
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.cloneVoicesTitle)),
      body: cloning.profiles.isEmpty
          ? Center(
              child: Text(
                l10n.noCloneVoices,
                style: AppText.caption,
              ),
            )
          : ListView.separated(
              itemCount: cloning.profiles.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final profile = cloning.profiles[i];
                return ListTile(
                  leading: const Icon(Icons.record_voice_over_outlined),
                  title: Text(profile.name),
                  subtitle: Text(
                    '${profile.sampleRate} Hz',
                    style: AppText.caption,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => cloning.deleteProfile(profile.id),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateSheet(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showCreateSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CreateCloneSheet(),
    );
  }
}

class _CreateCloneSheet extends StatefulWidget {
  const _CreateCloneSheet();

  @override
  State<_CreateCloneSheet> createState() => _CreateCloneSheetState();
}

class _CreateCloneSheetState extends State<_CreateCloneSheet> {
  final TextEditingController _name = TextEditingController();
  bool _recording = false;
  String? _refPath;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _record() async {
    final deps = context.read<AppDependencies>();
    await deps.micRecorder.hasPermission();
    final dir = deps.cloneRefsDir;
    await dir.create(recursive: true);
    final path = p.join(
      dir.path,
      'ref_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    await deps.micRecorder.start(path: path, sampleRate: 24000);
    setState(() => _recording = true);
    await Future<void>.delayed(const Duration(seconds: 3));
    await deps.micRecorder.stop();
    if (!mounted) return;
    setState(() {
      _recording = false;
      _refPath = path;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _refPath == null) return;
    await context.read<VoiceCloningService>().createProfile(name, _refPath!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            decoration: InputDecoration(
              labelText: l10n.cloneNameHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _recording ? null : _record,
            icon: Icon(_recording ? Icons.mic : Icons.mic_none),
            label: Text(_recording ? l10n.recording : l10n.recordReferenceHint),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: (_name.text.trim().isEmpty || _refPath == null)
                ? null
                : _save,
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }
}
