/// 长期记忆存储(跨会话、**按说话人隔离**的事实)。
///
/// 与知识库**分开存、分开删**:知识库是用户主动导入的资料,长期记忆是从对话推断的
/// 事实。合并会让"删除某人记忆"顺手删掉知识库(或反之),用户无法理解。
///
/// 两条硬约束:
/// 1. **按说话人过滤是每一次读写的默认动作**,不是可选优化。
///    把 A 的记忆注入给 B 是极难察觉的跨人泄漏(听起来还非常自然)。
/// 2. **`model_id` 参与读写**:换嵌入模型后旧向量不可比,而维度相同 ⇒
///    混用不报错,只让排序变噪音。
library;

import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import 'package:flutter_tts_demo/data/app_database.dart';
import 'package:flutter_tts_demo/data/models/memory_item.dart';
import 'package:flutter_tts_demo/utils/memory/vector_store.dart';

/// 一条待补向量的记忆(只取必需字段)。
class PendingMemory {
  const PendingMemory({required this.id, required this.content});

  final int id;
  final String content;
}

abstract class MemoryStore {
  /// 新增一条,返回自增 id。
  Future<int> insert({
    required String speaker,
    required String kind,
    required String content,
    required int createdAt,
    required int updatedAt,
    double confidence,
    int? sourceMsgId,
  });

  /// 按 id 更新内容(去重时 LLM 判 UPDATE 走这里)。
  Future<void> updateContent(
    int id, {
    required String kind,
    required String content,
    required double confidence,
    required int updatedAt,
  });

  Future<void> deleteById(int id);

  /// 某说话人的全部记忆(新的在前)。
  Future<List<MemoryItem>> bySpeaker(String speaker);

  /// 待补向量的记忆:没有向量,或向量属于别的模型。
  Future<List<PendingMemory>> pendingForEmbedding({
    required String modelId,
    required int limit,
  });

  Future<void> storeEmbedding({
    required int id,
    required String modelId,
    required Float32List vector,
  });

  /// 载入某模型 + 某说话人下**已嵌入**的候选。
  Future<List<VectorCandidate>> loadCandidates({
    required String modelId,
    required String speaker,
  });

  Future<void> clearSpeaker(String speaker);

  Future<void> clearAll();
}

class SqliteMemoryStore implements MemoryStore {
  SqliteMemoryStore(this._database);

  final AppDatabase _database;

  Database get _db => _database.db;

  @override
  Future<int> insert({
    required String speaker,
    required String kind,
    required String content,
    required int createdAt,
    required int updatedAt,
    double confidence = 0.7,
    int? sourceMsgId,
  }) {
    return _db.insert('memories', {
      'speaker': speaker,
      'kind': MemoryKind.normalize(kind),
      'content': content,
      'confidence': confidence,
      'source_msg_id': sourceMsgId,
      'created_at': createdAt,
      'updated_at': updatedAt,
    });
  }

  @override
  Future<void> updateContent(
    int id, {
    required String kind,
    required String content,
    required double confidence,
    required int updatedAt,
  }) async {
    // 内容变了,旧向量就不再对应该内容 ⇒ 一并清掉,让它重新排队补向量。
    // (留着旧向量会让检索按"改之前的意思"命中,是静默错误。)
    await _db.update(
      'memories',
      {
        'kind': MemoryKind.normalize(kind),
        'content': content,
        'confidence': confidence,
        'updated_at': updatedAt,
        'embedding': null,
        'dim': null,
        'model_id': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> deleteById(int id) async {
    await _db.delete('memories', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<List<MemoryItem>> bySpeaker(String speaker) async {
    final rows = await _db.query(
      'memories',
      where: 'speaker = ?',
      whereArgs: [speaker],
      orderBy: 'updated_at DESC, id DESC',
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<List<PendingMemory>> pendingForEmbedding({
    required String modelId,
    required int limit,
  }) async {
    final rows = await _db.query(
      'memories',
      columns: ['id', 'content'],
      where: 'embedding IS NULL OR model_id IS NULL OR model_id <> ?',
      whereArgs: [modelId],
      orderBy: 'id',
      limit: limit,
    );
    return rows
        .map((r) => PendingMemory(
              id: r['id'] as int,
              content: r['content'] as String,
            ))
        .toList();
  }

  @override
  Future<void> storeEmbedding({
    required int id,
    required String modelId,
    required Float32List vector,
  }) async {
    await _db.update(
      'memories',
      {
        'embedding': VectorCodec.encode(vector),
        'dim': vector.length,
        'model_id': modelId,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<List<VectorCandidate>> loadCandidates({
    required String modelId,
    required String speaker,
  }) async {
    final rows = await _db.query(
      'memories',
      columns: ['id', 'content', 'embedding', 'dim', 'confidence'],
      // 说话人过滤是**必需条件**,不是可选优化(见文件头)。
      where: 'speaker = ? AND embedding IS NOT NULL AND model_id = ?',
      whereArgs: [speaker, modelId],
    );
    final out = <VectorCandidate>[];
    for (final r in rows) {
      final blob = r['embedding'];
      if (blob is! Uint8List) continue;
      final vec = VectorCodec.decode(blob);
      final dim = (r['dim'] as int?) ?? vec.length;
      if (vec.length != dim) continue; // 脏数据跳过,不参与打分
      out.add(VectorCandidate(
        id: r['id'] as int,
        vector: vec,
        text: r['content'] as String,
        payload: r['confidence'] as double?,
      ));
    }
    return out;
  }

  @override
  Future<void> clearSpeaker(String speaker) async {
    await _db.delete('memories', where: 'speaker = ?', whereArgs: [speaker]);
  }

  @override
  Future<void> clearAll() async => _db.delete('memories');

  static MemoryItem _fromRow(Map<String, Object?> row) {
    final blob = row['embedding'];
    return MemoryItem(
      id: row['id'] as int,
      speaker: row['speaker'] as String,
      kind: row['kind'] as String,
      content: row['content'] as String,
      embedding: blob is Uint8List ? VectorCodec.decode(blob) : null,
      dim: row['dim'] as int?,
      modelId: row['model_id'] as String?,
      confidence: (row['confidence'] as num?)?.toDouble() ?? 0.7,
      sourceMsgId: row['source_msg_id'] as int?,
      createdAt: row['created_at'] as int,
      updatedAt: row['updated_at'] as int,
    );
  }
}

/// 内存实现(单元测试用)。
class MemoryMemoryStore implements MemoryStore {
  final Map<int, MemoryItem> _items = {};
  int _nextId = 1;

  @override
  Future<int> insert({
    required String speaker,
    required String kind,
    required String content,
    required int createdAt,
    required int updatedAt,
    double confidence = 0.7,
    int? sourceMsgId,
  }) async {
    final id = _nextId++;
    _items[id] = MemoryItem(
      id: id,
      speaker: speaker,
      kind: MemoryKind.normalize(kind),
      content: content,
      confidence: confidence,
      sourceMsgId: sourceMsgId,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
    return id;
  }

  @override
  Future<void> updateContent(
    int id, {
    required String kind,
    required String content,
    required double confidence,
    required int updatedAt,
  }) async {
    final old = _items[id];
    if (old == null) return;
    _items[id] = MemoryItem(
      id: id,
      speaker: old.speaker,
      kind: MemoryKind.normalize(kind),
      content: content,
      confidence: confidence,
      sourceMsgId: old.sourceMsgId,
      createdAt: old.createdAt,
      updatedAt: updatedAt,
      // 内容变了,旧向量作废(与 SQLite 实现一致)。
    );
  }

  @override
  Future<void> deleteById(int id) async => _items.remove(id);

  @override
  Future<List<MemoryItem>> bySpeaker(String speaker) async =>
      _items.values.where((m) => m.speaker == speaker).toList();

  @override
  Future<List<PendingMemory>> pendingForEmbedding({
    required String modelId,
    required int limit,
  }) async {
    final out = <PendingMemory>[];
    for (final m in _items.values) {
      if (m.embedding == null || m.modelId != modelId) {
        out.add(PendingMemory(id: m.id, content: m.content));
      }
      if (out.length >= limit) break;
    }
    return out;
  }

  @override
  Future<void> storeEmbedding({
    required int id,
    required String modelId,
    required Float32List vector,
  }) async {
    final old = _items[id];
    if (old == null) return;
    _items[id] = MemoryItem(
      id: old.id,
      speaker: old.speaker,
      kind: old.kind,
      content: old.content,
      embedding: vector,
      dim: vector.length,
      modelId: modelId,
      confidence: old.confidence,
      sourceMsgId: old.sourceMsgId,
      createdAt: old.createdAt,
      updatedAt: old.updatedAt,
    );
  }

  @override
  Future<List<VectorCandidate>> loadCandidates({
    required String modelId,
    required String speaker,
  }) async {
    final out = <VectorCandidate>[];
    for (final m in _items.values) {
      if (m.speaker != speaker) continue;
      if (m.embedding == null || m.modelId != modelId) continue;
      out.add(VectorCandidate(
        id: m.id,
        vector: m.embedding!,
        text: m.content,
        payload: m.confidence,
      ));
    }
    return out;
  }

  @override
  Future<void> clearSpeaker(String speaker) async =>
      _items.removeWhere((_, m) => m.speaker == speaker);

  @override
  Future<void> clearAll() async => _items.clear();
}
