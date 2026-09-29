/// 知识库管理页:文档列表(含索引进度)+ 导入 + 删除 + **检索试跑**。
///
/// 「检索试跑」是刻意放的:检索质量不可见时,用户与开发者都只能猜。
/// 有了它,"导入了却检索不到"能被一眼看穿(分数会明说)。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tts_demo/components/theme/app_text.dart';
import 'package:flutter_tts_demo/data/models/kb_document.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';
import 'package:flutter_tts_demo/utils/memory/knowledge_service.dart';
import 'package:flutter_tts_demo/utils/memory/vector_store.dart';

class KnowledgePage extends StatefulWidget {
  const KnowledgePage({super.key});

  @override
  State<KnowledgePage> createState() => _KnowledgePageState();
}

class _KnowledgePageState extends State<KnowledgePage> {
  final _probeController = TextEditingController();
  List<VectorHit>? _probeResults;

  @override
  void initState() {
    super.initState();
    // 打开时刷新一次:进度可能在别处(后台回填)已经变了。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<KnowledgeService>().refresh();
    });
  }

  @override
  void dispose() {
    _probeController.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final service = context.read<KnowledgeService>();
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<({String title, String text})>(
      context: context,
      builder: (ctx) => _ImportDialog(l10n: l10n),
    );
    if (result == null || !mounted) return;
    try {
      final r = await service.importText(title: result.title, text: result.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.kbImportDone(r.chunkCount))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _probe() async {
    final service = context.read<KnowledgeService>();
    final hits = await service.search(_probeController.text);
    if (!mounted) return;
    setState(() => _probeResults = hits);
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<KnowledgeService>();
    final l10n = AppLocalizations.of(context);
    final docs = service.documents;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.kbManageTitle),
        actions: [
          IconButton(
            key: const ValueKey('kbImportButton'),
            icon: const Icon(Icons.add),
            tooltip: l10n.kbImportText,
            onPressed: _import,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 模型没下就明说 —— 否则用户会以为"导入了就能检索"。
          if (!service.isModelReady)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(l10n.kbNoEmbeddingModel, style: AppText.body),
              ),
            ),
          if (service.isIndexing || service.pendingChunks > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  if (service.isIndexing)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.kbIndexPendingHint(service.pendingChunks),
                      key: const ValueKey('kbPendingHint'),
                      style: AppText.caption,
                    ),
                  ),
                  if (!service.isIndexing)
                    TextButton(
                      key: const ValueKey('kbIndexNowButton'),
                      onPressed: service.startBackfill,
                      child: Text(l10n.kbImport),
                    ),
                ],
              ),
            ),
          if (docs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(l10n.kbEmpty,
                  style: AppText.tertiary(AppText.body), textAlign: TextAlign.center),
            )
          else
            ...docs.map((d) => _DocumentTile(doc: d, service: service)),
          const Divider(height: 32),
          Text(l10n.kbSearchProbe, style: AppText.body),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('kbProbeField'),
                  controller: _probeController,
                  decoration: InputDecoration(
                    hintText: l10n.kbSearchHint,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _probe(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const ValueKey('kbProbeButton'),
                onPressed: _probe,
                child: Text(l10n.kbSearchProbe),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_probeResults != null)
            if (_probeResults!.isEmpty)
              Text(l10n.kbSearchNoResult, style: AppText.caption)
            else
              ..._probeResults!.map((h) => Card(
                    child: ListTile(
                      dense: true,
                      title: Text(h.text ?? '', style: AppText.caption),
                      subtitle: Text(
                        l10n.kbSearchScore(h.score.toStringAsFixed(3)),
                        style: AppText.caption,
                      ),
                    ),
                  )),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({required this.doc, required this.service});

  final KbDocument doc;
  final KnowledgeService service;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final indexing = doc.isIndexing;
    return Card(
      child: ListTile(
        title: Text(doc.title, style: AppText.body),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (indexing)
              Text(l10n.kbIndexing(doc.embeddedCount, doc.chunkCount),
                  style: AppText.caption)
            else
              Text(l10n.kbIndexed(doc.chunkCount), style: AppText.caption),
            if (indexing)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: LinearProgressIndicator(value: doc.indexProgress),
              ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: l10n.kbDelete,
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                content: Text(l10n.kbDeleteConfirm),
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
            if (ok ?? false) await service.deleteDocument(doc.id);
          },
        ),
      ),
    );
  }
}

/// 导入对话框:标题 + 大段文本。
class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.l10n});

  final AppLocalizations l10n;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _title = TextEditingController();
  final _content = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.l10n.kbImportText),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('kbImportTitleField'),
              controller: _title,
              decoration: InputDecoration(
                hintText: widget.l10n.kbImportTitleHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('kbImportContentField'),
              controller: _content,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: widget.l10n.kbImportContentHint,
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: AppText.caption),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        TextButton(
          key: const ValueKey('kbImportConfirm'),
          onPressed: () {
            final t = _title.text.trim();
            final c = _content.text.trim();
            if (t.isEmpty || c.isEmpty) {
              setState(() => _error = widget.l10n.kbImportEmpty);
              return;
            }
            Navigator.pop(context, (title: t, text: c));
          },
          child: Text(widget.l10n.kbImport),
        ),
      ],
    );
  }
}
