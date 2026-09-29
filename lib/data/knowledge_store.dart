/// 知识库存储(文档 / 切块 / 向量)。
///
/// 设计与"静默错误"相关的两条硬约束:
///
/// 1. **`embedding` 可空是核心**:导入**只同步落文本**(embedding = NULL),
///    向量在后台分批回填。检索只取已嵌入的块 ⇒ 未索引完的文档**部分可检索**,
///    用户不必对着转圈对话框等几分钟。
///
/// 2. **`model_id` 必须参与每一次读写**:换嵌入模型后新旧向量不可比,而两者维度
///    相同、混用**不会报错**,只会让相似度排序变成噪音。故:
///    - 待回填的判据是 `embedding IS NULL **OR** model_id <> 当前模型`
///      ⇒ 换模型会自动触发重建,不需要额外的"重建索引"按钮;
///    - 检索只取 `model_id == 当前模型` 的块。
library;

import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import 'package:flutter_tts_demo/data/app_database.dart';
import 'package:flutter_tts_demo/data/models/kb_document.dart';
import 'package:flutter_tts_demo/utils/memory/vector_store.dart';

/// 一条待回填向量的块(只取回填必需的最小字段)。
class PendingChunk {
  const PendingChunk({required this.id, required this.text});

  final int id;
  final String text;
}

abstract class KnowledgeStore {
  /// 插入文档并返回自增 id。
  Future<int> insertDocument({
    required String title,
    String? sourcePath,
    required int charCount,
    required int chunkCount,
    required int importedAt,
  });

  /// 批量插入切块(此时都还没有向量)。
  Future<void> insertChunks(int docId, List<String> texts);

  /// 文档列表。
  ///
  /// **必须带 [modelId]**:索引进度是"相对当前嵌入模型"而言的 ——
  /// 换模型后旧向量需要重建,进度不能沿用。
  Future<List<KbDocument>> documents({required String modelId});

  Future<void> deleteDocument(int docId);

  /// 待回填的块:没有向量,或向量是用**别的模型**算的。
  Future<List<PendingChunk>> pendingChunks({
    required String modelId,
    required int limit,
  });

  /// 写入一批向量。
  Future<void> storeEmbeddings({
    required String modelId,
    required List<(int id, Float32List vector)> items,
  });

  /// 取某文档的块数。
  Future<int> chunkCount(int docId);

  /// 载入某模型下**全部已嵌入**的候选(供内存暴力检索)。
  Future<List<VectorCandidate>> loadCandidates({required String modelId});

  /// 清空知识库(文档 + 切块)。
  Future<void> clearAll();
}

class SqliteKnowledgeStore implements KnowledgeStore {
  SqliteKnowledgeStore(this._database);

  final AppDatabase _database;

  Database get _db => _database.db;

  @override
  Future<int> insertDocument({
    required String title,
    String? sourcePath,
    required int charCount,
    required int chunkCount,
    required int importedAt,
  }) {
    return _db.insert('kb_documents', {
      'title': title,
      'source_path': sourcePath,
      'imported_at': importedAt,
      'char_count': charCount,
      'chunk_count': chunkCount,
    });
  }

  @override
  Future<void> insertChunks(int docId, List<String> texts) async {
    // 事务:要么整篇的块都进去,要么都不进 —— 半篇会导致"切块数对不上正文"。
    await _db.transaction((txn) async {
      for (var i = 0; i < texts.length; i++) {
        await txn.insert('kb_chunks', {
          'doc_id': docId,
          'seq': i,
          'text': texts[i],
        });
      }
    });
  }

  @override
  Future<List<KbDocument>> documents({required String modelId}) async {
    // 一条聚合查询拿到每篇的"已按当前模型索引"的块数 —— 避免 N+1,也避免
    // 把进度存成列后在换模型时失真。
    final stats = await _db.rawQuery(
      'SELECT doc_id, '
      'COUNT(*) AS total, '
      'SUM(CASE WHEN embedding IS NOT NULL AND model_id = ? THEN 1 ELSE 0 END) AS embedded '
      'FROM kb_chunks GROUP BY doc_id',
      [modelId],
    );
    final embeddedByDoc = <int, int>{};
    for (final r in stats) {
      embeddedByDoc[r['doc_id'] as int] = (r['embedded'] as num?)?.toInt() ?? 0;
    }

    final rows =
        await _db.query('kb_documents', orderBy: 'imported_at DESC, id DESC');
    return rows
        .map((r) => KbDocument(
              id: r['id'] as int,
              title: r['title'] as String,
              sourcePath: r['source_path'] as String?,
              importedAt: r['imported_at'] as int,
              charCount: r['char_count'] as int,
              chunkCount: r['chunk_count'] as int,
              embeddedCount: embeddedByDoc[r['id'] as int] ?? 0,
            ))
        .toList();
  }

  @override
  Future<void> deleteDocument(int docId) async {
    // 连带删块:留着会变成永远检索不到、也永远回填不完的孤儿数据。
    await _db.transaction((txn) async {
      await txn.delete('kb_chunks', where: 'doc_id = ?', whereArgs: [docId]);
      await txn.delete('kb_documents', where: 'id = ?', whereArgs: [docId]);
    });
  }

  @override
  Future<List<PendingChunk>> pendingChunks({
    required String modelId,
    required int limit,
  }) async {
    final rows = await _db.query(
      'kb_chunks',
      columns: ['id', 'text'],
      // 没向量、或向量是用别的模型算的 —— 后者保证"换模型自动重建索引"。
      where: 'embedding IS NULL OR model_id IS NULL OR model_id <> ?',
      whereArgs: [modelId],
      orderBy: 'id',
      limit: limit,
    );
    return rows
        .map((r) => PendingChunk(id: r['id'] as int, text: r['text'] as String))
        .toList();
  }

  @override
  Future<void> storeEmbeddings({
    required String modelId,
    required List<(int id, Float32List vector)> items,
  }) async {
    await _db.transaction((txn) async {
      for (final (id, vector) in items) {
        await txn.update(
          'kb_chunks',
          {
            'embedding': VectorCodec.encode(vector),
            'dim': vector.length,
            'model_id': modelId,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    });
  }

  @override
  Future<int> chunkCount(int docId) async {
    final r = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM kb_chunks WHERE doc_id = ?',
      [docId],
    );
    return (r.first['c'] as int?) ?? 0;
  }

  @override
  Future<List<VectorCandidate>> loadCandidates({required String modelId}) async {
    final rows = await _db.query(
      'kb_chunks',
      columns: ['id', 'doc_id', 'text', 'embedding', 'dim'],
      where: 'embedding IS NOT NULL AND model_id = ?',
      whereArgs: [modelId],
    );
    final out = <VectorCandidate>[];
    for (final r in rows) {
      final blob = r['embedding'];
      if (blob is! Uint8List) continue;
      final vec = VectorCodec.decode(blob);
      final dim = (r['dim'] as int?) ?? vec.length;
      // 维度对不上说明这行是脏数据(例如手工改过库)⇒ 跳过,不让它参与打分。
      if (vec.length != dim) continue;
      out.add(VectorCandidate(
        id: r['id'] as int,
        vector: vec,
        text: r['text'] as String,
        payload: r['doc_id'] as int,
      ));
    }
    return out;
  }

  @override
  Future<void> clearAll() async {
    await _db.transaction((txn) async {
      await txn.delete('kb_chunks');
      await txn.delete('kb_documents');
    });
  }
}

/// 内存实现(单元测试用,不依赖 sqflite)。
class MemoryKnowledgeStore implements KnowledgeStore {
  final Map<int, KbDocument> _docs = {};
  final Map<int, List<KbChunkRecord>> _chunks = {};
  int _nextDocId = 1;
  int _nextChunkId = 1;

  /// 记录写入过的向量,便于断言"回填用哪个 modelId"。
  final List<String> storedModelIds = [];

  @override
  Future<int> insertDocument({
    required String title,
    String? sourcePath,
    required int charCount,
    required int chunkCount,
    required int importedAt,
  }) async {
    final id = _nextDocId++;
    _docs[id] = KbDocument(
      id: id,
      title: title,
      sourcePath: sourcePath,
      importedAt: importedAt,
      charCount: charCount,
      chunkCount: chunkCount,
      embeddedCount: 0,
    );
    _chunks[id] = [];
    return id;
  }

  @override
  Future<void> insertChunks(int docId, List<String> texts) async {
    final list = _chunks.putIfAbsent(docId, () => []);
    for (var i = 0; i < texts.length; i++) {
      list.add(KbChunkRecord(
        id: _nextChunkId++,
        docId: docId,
        seq: i,
        text: texts[i],
      ));
    }
  }

  @override
  Future<List<KbDocument>> documents({required String modelId}) async => _docs.values.map((d) {
    final list = _chunks[d.id] ?? const <KbChunkRecord>[];
    return KbDocument(
      id: d.id,
      title: d.title,
      sourcePath: d.sourcePath,
      importedAt: d.importedAt,
      charCount: d.charCount,
      chunkCount: d.chunkCount,
      embeddedCount:
          list.where((c) => c.embedding != null && c.modelId == modelId).length,
    );
  }).toList();

  @override
  Future<void> deleteDocument(int docId) async {
    _docs.remove(docId);
    _chunks.remove(docId);
  }

  @override
  Future<List<PendingChunk>> pendingChunks({
    required String modelId,
    required int limit,
  }) async {
    final out = <PendingChunk>[];
    for (final list in _chunks.values) {
      for (final c in list) {
        // 与 SQL 同义:没向量,或向量属于别的模型。
        if (c.embedding == null || c.modelId == null || c.modelId != modelId) {
          out.add(PendingChunk(id: c.id, text: c.text));
        }
        if (out.length >= limit) return out;
      }
    }
    return out;
  }

  @override
  Future<void> storeEmbeddings({
    required String modelId,
    required List<(int id, Float32List vector)> items,
  }) async {
    storedModelIds.add(modelId);
    final byId = {for (final (id, v) in items) id: v};
    for (final entry in _chunks.entries) {
      final list = entry.value;
      for (var i = 0; i < list.length; i++) {
        final v = byId[list[i].id];
        if (v == null) continue;
        list[i] = KbChunkRecord(
          id: list[i].id,
          docId: list[i].docId,
          seq: list[i].seq,
          text: list[i].text,
          embedding: v,
          dim: v.length,
          modelId: modelId,
        );
      }
    }
  }

  @override
  Future<int> chunkCount(int docId) async => _chunks[docId]?.length ?? 0;

  @override
  Future<List<VectorCandidate>> loadCandidates({required String modelId}) async {
    final out = <VectorCandidate>[];
    for (final list in _chunks.values) {
      for (final c in list) {
        if (c.embedding == null || c.modelId != modelId) continue;
        out.add(VectorCandidate(
          id: c.id,
          vector: c.embedding!,
          text: c.text,
          payload: c.docId,
        ));
      }
    }
    return out;
  }

  @override
  Future<void> clearAll() async {
    _docs.clear();
    _chunks.clear();
  }

  /// 测试辅助:直接塞入一个已嵌入的块。
  void putEmbedded(int docId, String text, Float32List vector, String modelId) {
    final list = _chunks.putIfAbsent(docId, () => []);
    list.add(KbChunkRecord(
      id: _nextChunkId++,
      docId: docId,
      seq: list.length,
      text: text,
      embedding: vector,
      dim: vector.length,
      modelId: modelId,
    ));
  }
}
