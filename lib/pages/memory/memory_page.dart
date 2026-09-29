/// 记忆管理页:按**说话人**分组列出长期记忆,可单条删除或清空某人。
///
/// 说话人列表取自**声纹库**:记忆只属于已注册说话人(未注册者根本不被抽取),
/// 所以从声纹库枚举既准确又不会漏。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tts_demo/components/theme/app_text.dart';
import 'package:flutter_tts_demo/data/models/memory_item.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';
import 'package:flutter_tts_demo/utils/memory/memory_service.dart';
import 'package:flutter_tts_demo/utils/voiceprint_service.dart';

class MemoryPage extends StatefulWidget {
  const MemoryPage({super.key});

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> {
  /// 说话人 → 其记忆列表。
  Map<String, List<MemoryItem>> _bySpeaker = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final memory = context.read<MemoryService>();
    final voiceprint = context.read<VoiceprintService>();
    final names = <String>{
      for (final p in voiceprint.profiles) p.name,
    };
    final result = <String, List<MemoryItem>>{};
    for (final n in names) {
      final items = await memory.listFor(n);
      if (items.isNotEmpty) result[n] = items;
    }
    if (!mounted) return;
    setState(() {
      _bySpeaker = result;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.memoryManageTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _bySpeaker.isEmpty
              ? Center(
                  child: Text(l10n.memoryEmpty,
                      style: AppText.tertiary(AppText.body)),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final entry in _bySpeaker.entries)
                      _SpeakerGroup(
                        speaker: entry.key,
                        items: entry.value,
                        onChanged: _reload,
                      ),
                    const SizedBox(height: 32),
                  ],
                ),
    );
  }
}

class _SpeakerGroup extends StatelessWidget {
  const _SpeakerGroup({
    required this.speaker,
    required this.items,
    required this.onChanged,
  });

  final String speaker;
  final List<MemoryItem> items;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final memory = context.read<MemoryService>();
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text('$speaker · ${l10n.memoryCount(items.length)}',
                style: AppText.body),
            trailing: TextButton(
              key: ValueKey('memoryClear_$speaker'),
              onPressed: () async {
                final ok = await _confirm(context, l10n.memoryDeleteAllConfirm);
                if (ok) {
                  await memory.clearSpeaker(speaker);
                  await onChanged();
                }
              },
              child: Text(l10n.memoryDeleteAll),
            ),
          ),
          const Divider(height: 1),
          for (final m in items)
            ListTile(
              dense: true,
              title: Text(m.content, style: AppText.body),
              subtitle: Text(
                '${m.kind} · ${m.confidence.toStringAsFixed(2)}',
                style: AppText.caption,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () async {
                  await memory.deleteById(m.id);
                  await onChanged();
                },
              ),
            ),
        ],
      ),
    );
  }
}

Future<bool> _confirm(BuildContext context, String message) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}
