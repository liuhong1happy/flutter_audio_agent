/// `AppDatabase` 版本化迁移测试。
///
/// 守的是一条硬不变量:**升级只增不改不删,历史数据必须原样保留**。
/// 迁移写错的后果是用户升级后会话历史凭空消失 —— 而且只在"老库升级"路径上发生,
/// 全新安装完全看不出来,所以必须专门测。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_tts_demo/data/app_database.dart';

/// 手工造一个 **v1** 老库(模拟引入知识库/记忆之前的安装)。
Future<void> createV1Database(String path) async {
  final db = await openDatabase(
    path,
    version: 1,
    onCreate: (db, _) async {
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
    },
  );
  await db.insert('conversation_messages', {
    'role': 'user',
    'content': '老库里的历史消息',
    'speaker': '张三',
    'created_at': 1700000000000,
  });
  await db.insert('conversation_messages', {
    'role': 'assistant',
    'content': '老库里的回复',
    'speaker': null,
    'created_at': 1700000001000,
  });
  await db.close();
}

Future<Set<String>> tableNames(AppDatabase db) async {
  final rows = await db.db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table'",
  );
  return rows.map((r) => r['name'] as String).toSet();
}

Future<Set<String>> columnNames(AppDatabase db, String table) async {
  final rows = await db.db.rawQuery('PRAGMA table_info($table)');
  return rows.map((r) => r['name'] as String).toSet();
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('appdb_');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('v1 → v2:老库的历史消息**一条不丢**', () async {
    final path = '${dir.path}/conversation.db';
    await createV1Database(path);

    final db = AppDatabase(path);
    await db.open();
    addTearDown(db.close);

    final rows = await db.db.query('conversation_messages', orderBy: 'id');
    expect(rows.length, 2, reason: '迁移不能丢历史数据');
    expect(rows[0]['content'], '老库里的历史消息');
    expect(rows[0]['speaker'], '张三');
    expect(rows[1]['content'], '老库里的回复');
  });

  test('v1 → v2:新增 session_id 列并回填 legacy(不假装知道历史会话边界)', () async {
    final path = '${dir.path}/conversation.db';
    await createV1Database(path);

    final db = AppDatabase(path);
    await db.open();
    addTearDown(db.close);

    expect(await columnNames(db, 'conversation_messages'), contains('session_id'));
    final rows = await db.db.query('conversation_messages');
    for (final r in rows) {
      expect(r['session_id'], 'legacy',
          reason: '引入分段概念之前的历史,统一归入 legacy');
    }
  });

  test('v1 → v2:知识库/记忆/摘要三张表被建出来', () async {
    final path = '${dir.path}/conversation.db';
    await createV1Database(path);

    final db = AppDatabase(path);
    await db.open();
    addTearDown(db.close);

    final tables = await tableNames(db);
    expect(tables, containsAll(<String>[
      'conversation_messages',
      'session_summaries',
      'kb_documents',
      'kb_chunks',
      'memories',
    ]));
  });

  test('v1 → v2:kb_chunks 的关键列齐(multi-model 隔离靠 model_id)', () async {
    final path = '${dir.path}/conversation.db';
    await createV1Database(path);

    final db = AppDatabase(path);
    await db.open();
    addTearDown(db.close);

    // `embedding` 可空是核心设计(支持"导入瞬时完成、向量后台回填");
    // `model_id` 不可省(换模型后向量不可比,而维度相同 ⇒ 混用不报错只变噪音)。
    expect(await columnNames(db, 'kb_chunks'),
        containsAll(<String>['doc_id', 'seq', 'text', 'embedding', 'dim', 'model_id']));
    expect(await columnNames(db, 'memories'),
        containsAll(<String>['speaker', 'kind', 'content', 'embedding', 'model_id', 'confidence']));
  });

  test('全新安装与老库升级得到**同样的表结构**(两条路径不能漂)', () async {
    // 老库升级路径
    final upgradedPath = '${dir.path}/upgraded.db';
    await createV1Database(upgradedPath);
    final upgraded = AppDatabase(upgradedPath);
    await upgraded.open();
    addTearDown(upgraded.close);
    final upgradedTables = await tableNames(upgraded);

    // 全新安装路径
    final freshPath = '${dir.path}/fresh.db';
    final fresh = AppDatabase(freshPath);
    await fresh.open();
    addTearDown(fresh.close);
    final freshTables = await tableNames(fresh);

    // sqlite 内部表(android_metadata 等)允许差异,只比业务表。
    const businessTables = {
      'conversation_messages',
      'session_summaries',
      'kb_documents',
      'kb_chunks',
      'memories',
    };
    expect(upgradedTables.where(businessTables.contains).toSet(),
        freshTables.where(businessTables.contains).toSet());
    // 列也必须一致 —— onCreate 与 migration 漂了就会出现"新装能用、老库升上来不能用"。
    for (final t in businessTables) {
      expect(await columnNames(upgraded, t), await columnNames(fresh, t),
          reason: '表 $t 的列在老库升级与新装之间不一致');
    }
  });

  test('重复 open 幂等', () async {
    final path = '${dir.path}/conversation.db';
    final db = AppDatabase(path);
    await db.open();
    addTearDown(db.close);
    await db.open(); // 不应抛错
    expect(db.isOpen, isTrue);
  });
}
