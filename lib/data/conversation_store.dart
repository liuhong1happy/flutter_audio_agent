/// 会话历史存储抽象 + SQLite 实现。
///
/// 单一时间线(不分说话人桶),按时间/id 排序,支持分页查询。
/// SQLite 实现用 sqflite 的 `version` + `onCreate` + `onUpgrade` 做版本化
/// 表结构升级,历史数据在迁移时无缝保留(迁移只 ALTER/CREATE,不删数据)。
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

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

/// 基于 sqflite 的 SQLite 实现,带版本化表结构迁移。
class SqliteConversationStore implements ConversationStore {
  SqliteConversationStore(this._dbPath);

  final String _dbPath;
  Database? _db;

  /// 当前表结构版本。结构变更时 +1,并在 [_migrations] 注册对应迁移步骤。
  static const int _version = 1;

  @override
  Future<void> open() async {
    final dir = p.dirname(_dbPath);
    await Directory(dir).create(recursive: true);
    _db = await openDatabase(
      _dbPath,
      version: _version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE conversation_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        speaker TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_conversation_id ON conversation_messages(id)',
    );
  }

  /// 版本化迁移:按序执行 (oldVersion, newVersion] 之间的迁移步骤。
  ///
  /// 新增字段/表时,只在这里追加 `newVersion -> 迁移函数`,并对旧版本数据
  /// 做 `ALTER TABLE ... ADD COLUMN` / 回填默认值,即可无缝升级且不丢历史。
  static const Map<int, Future<void> Function(Database db)> _migrations = {
    // 2: _migrateV1ToV2, // 未来示例:ALTER TABLE 新增列并回填。
  };

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    for (var v = oldVersion + 1; v <= newVersion; v++) {
      final migrate = _migrations[v];
      if (migrate != null) {
        await migrate(db);
      }
    }
  }

  @override
  Future<int> insert(ConversationMessage message) async {
    return _db!.insert('conversation_messages', <String, Object?>{
      'role': message.role.name,
      'content': message.content,
      'speaker': message.speakerName,
      'created_at': message.createdAt,
    });
  }

  @override
  Future<List<ConversationMessage>> recent({int limit = 50}) async {
    final rows = await _db!.query(
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
    final rows = await _db!.query(
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
    final r = await _db!.rawQuery(
      'SELECT COUNT(*) AS c FROM conversation_messages',
    );
    return (r.first['c'] as int?) ?? 0;
  }

  @override
  Future<void> deleteById(int id) async {
    await _db!.delete('conversation_messages', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> clearAll() async => _db!.delete('conversation_messages');

  @override
  Future<void> close() async => _db?.close();

  static ConversationMessage _fromRow(Map<String, Object?> row) {
    return ConversationMessage(
      id: row['id'] as int,
      role: row['role'] == 'assistant'
          ? ConversationRole.assistant
          : ConversationRole.user,
      content: row['content'] as String,
      speakerName: row['speaker'] as String?,
      createdAt: row['created_at'] as int,
    );
  }
}
