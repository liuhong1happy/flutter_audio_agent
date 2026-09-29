/// 短期记忆的存储:会话摘要 + 摘要水位线。
///
/// 只存**摘要**与**水位线**,不存原文 —— 原文只在 `conversation_messages` 里。
/// 短期记忆是它的**上层压缩视图**,不是第二份消息存储(造两份就是两处真相)。
library;

import 'package:sqflite/sqflite.dart';

import 'package:flutter_tts_demo/data/app_database.dart';
import 'package:flutter_tts_demo/data/models/conversation_message.dart';

/// 一个会话段的摘要。
class SessionSummary {
  const SessionSummary({
    required this.sessionId,
    required this.summary,
    required this.summarizedUpToId,
    required this.updatedAt,
  });

  final String sessionId;
  final String summary;

  /// **水位线**:只摘要 id 大于它的消息。
  ///
  /// 这是"增量"的全部秘密 —— 每次都只把"新增的若干条 + 已有摘要"合成新摘要,
  /// 而不是把整场会话重摘一遍(那是 O(n²) 的 token 消耗)。
  final int summarizedUpToId;

  final int updatedAt;

  @override
  String toString() =>
      'SessionSummary($sessionId, upTo=$summarizedUpToId, ${summary.length}字)';
}

abstract class SessionMemoryStore {
  Future<SessionSummary?> get(String sessionId);

  Future<void> put({
    required String sessionId,
    required String summary,
    required int summarizedUpToId,
    required int updatedAt,
  });

  /// 水位线之后、尚未摘要的消息(升序)。
  Future<List<ConversationMessage>> unsummarized({
    required String sessionId,
    required int afterId,
    required int limit,
  });

  /// 水位线之后、尚未摘要的消息条数。
  Future<int> countUnsummarized({
    required String sessionId,
    required int afterId,
  });

  Future<void> clearAll();
}

class SqliteSessionMemoryStore implements SessionMemoryStore {
  SqliteSessionMemoryStore(this._database);

  final AppDatabase _database;

  Database get _db => _database.db;

  @override
  Future<SessionSummary?> get(String sessionId) async {
    final rows = await _db.query(
      'session_summaries',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    return SessionSummary(
      sessionId: r['session_id'] as String,
      summary: r['summary'] as String,
      summarizedUpToId: r['summarized_up_to_id'] as int,
      updatedAt: r['updated_at'] as int,
    );
  }

  @override
  Future<void> put({
    required String sessionId,
    required String summary,
    required int summarizedUpToId,
    required int updatedAt,
  }) async {
    await _db.insert(
      'session_summaries',
      {
        'session_id': sessionId,
        'summary': summary,
        'summarized_up_to_id': summarizedUpToId,
        'updated_at': updatedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<ConversationMessage>> unsummarized({
    required String sessionId,
    required int afterId,
    required int limit,
  }) async {
    final rows = await _db.query(
      'conversation_messages',
      where: 'session_id = ? AND id > ?',
      whereArgs: [sessionId, afterId],
      orderBy: 'id ASC',
      limit: limit,
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<int> countUnsummarized({
    required String sessionId,
    required int afterId,
  }) async {
    final r = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM conversation_messages '
      'WHERE session_id = ? AND id > ?',
      [sessionId, afterId],
    );
    return (r.first['c'] as int?) ?? 0;
  }

  @override
  Future<void> clearAll() async => _db.delete('session_summaries');

  static ConversationMessage _fromRow(Map<String, Object?> row) {
    return ConversationMessage(
      id: row['id'] as int,
      role: row['role'] == 'assistant'
          ? ConversationRole.assistant
          : ConversationRole.user,
      content: row['content'] as String,
      speakerName: row['speaker'] as String?,
      createdAt: row['created_at'] as int,
      sessionId: row['session_id'] as String?,
    );
  }
}

/// 内存实现(单元测试用)。
class MemorySessionMemoryStore implements SessionMemoryStore {
  final Map<String, SessionSummary> _summaries = {};
  final List<ConversationMessage> _messages = [];
  int _nextId = 1;

  /// 测试辅助:塞入一条消息(自动分配 id)。
  ConversationMessage addMessage({
    required String sessionId,
    required String content,
    String? speakerName,
    ConversationRole role = ConversationRole.user,
    int createdAt = 0,
  }) {
    final m = ConversationMessage(
      id: _nextId++,
      role: role,
      content: content,
      speakerName: speakerName,
      createdAt: createdAt,
      sessionId: sessionId,
    );
    _messages.add(m);
    return m;
  }

  @override
  Future<SessionSummary?> get(String sessionId) async => _summaries[sessionId];

  @override
  Future<void> put({
    required String sessionId,
    required String summary,
    required int summarizedUpToId,
    required int updatedAt,
  }) async {
    _summaries[sessionId] = SessionSummary(
      sessionId: sessionId,
      summary: summary,
      summarizedUpToId: summarizedUpToId,
      updatedAt: updatedAt,
    );
  }

  @override
  Future<List<ConversationMessage>> unsummarized({
    required String sessionId,
    required int afterId,
    required int limit,
  }) async {
    final out = <ConversationMessage>[];
    for (final m in _messages) {
      if (m.sessionId != sessionId) continue;
      if ((m.id ?? 0) <= afterId) continue;
      out.add(m);
      if (out.length >= limit) break;
    }
    return out;
  }

  @override
  Future<int> countUnsummarized({
    required String sessionId,
    required int afterId,
  }) async {
    return _messages
        .where((m) => m.sessionId == sessionId && (m.id ?? 0) > afterId)
        .length;
  }

  @override
  Future<void> clearAll() async {
    _summaries.clear();
    _messages.clear();
  }
}
