/// 会话历史存储抽象 + SQLite 实现。
///
/// 单一时间线(不分说话人桶),按时间/id 排序,支持分页查询。
///
/// **库结构与迁移在 [AppDatabase]**(知识库/记忆共用同一个库文件,迁移只能有一处);
/// 本文件只负责 `conversation_messages` 的读写。
library;




import 'package:sqflite/sqflite.dart';

import 'package:flutter_tts_demo/data/app_database.dart';

import 'package:flutter_tts_demo/data/models/conversation_message.dart';

/// 会话历史存储接口(便于测试注入内存实现)。
abstract class ConversationStore {
  Future<void> open();

  /// 插入一条消息,返回自增 id。
  Future<int> insert(ConversationMessage message);

  /// 最近 [limit] 条(按时间升序,旧→新)。
  Future<List<ConversationMessage>> recent({int limit = 50});

  /// id 小于 [beforeId] 的 [limit] 条(升序,旧→新,用于向前翻页)。
  Future<List<ConversationMessage>> olderThan({
    required int beforeId,
    int limit = 20,
  });

  Future<int> count();

  Future<void> deleteById(int id);

  Future<void> clearAll();

  Future<void> close();
}

/// 基于 sqflite 的 SQLite 实现。
///
/// **库结构与迁移已上移到 [AppDatabase]**(知识库/记忆共用同一个库文件,
/// 迁移必须只有一处,否则各 store 各开连接、各自升级,版本与顺序会打架)。
/// 本类只做 `conversation_messages` 的读写。
class SqliteConversationStore implements ConversationStore {
  SqliteConversationStore(this._database);

  final AppDatabase _database;

  Database get _db => _database.db;

  @override
  Future<void> open() => _database.open();

  @override
  Future<int> insert(ConversationMessage message) async {
    return _db.insert('conversation_messages', <String, Object?>{
      'role': message.role.name,
      'content': message.content,
      'speaker': message.speakerName,
      'created_at': message.createdAt,
      'session_id': message.sessionId,
    });
  }

  @override
  Future<List<ConversationMessage>> recent({int limit = 50}) async {
    final rows = await _db.query(
      'conversation_messages',
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.reversed.map(_fromRow).toList();
  }

  @override
  Future<List<ConversationMessage>> olderThan({
    required int beforeId,
    int limit = 20,
  }) async {
    final rows = await _db.query(
      'conversation_messages',
      where: 'id < ?',
      whereArgs: [beforeId],
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.reversed.map(_fromRow).toList();
  }

  @override
  Future<int> count() async {
    final r = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM conversation_messages',
    );
    return (r.first['c'] as int?) ?? 0;
  }

  @override
  Future<void> deleteById(int id) async {
    await _db.delete('conversation_messages', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> clearAll() async => _db.delete('conversation_messages');

  /// ⚠️ **故意不关库**:库由 [AppDatabase] 持有,知识库/记忆的 store 共用同一个连接。
  /// 在这里关掉会连带把它们的连接一起关掉(而它们并不知道)。
  /// 生命周期由 [AppDatabase.close] 统一负责。
  @override
  Future<void> close() async {}

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
