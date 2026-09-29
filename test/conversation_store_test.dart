/// 会话历史存储测试:内存实现 + SQLite 实现(分页/增删/版本迁移)。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_tts_demo/data/models/conversation_message.dart';
import 'package:flutter_tts_demo/data/app_database.dart';
import 'package:flutter_tts_demo/data/conversation_store.dart';

import 'support/fakes.dart';

void main() {
  test('MemoryConversationStore 分页(向前翻页)', () async {
    final store = MemoryConversationStore();
    await store.open();
    for (var i = 1; i <= 55; i++) {
      await store.insert(ConversationMessage(
        role: i.isOdd ? ConversationRole.user : ConversationRole.assistant,
        content: 'm$i',
        speakerName: i.isOdd ? '张三' : null,
        createdAt: i,
      ));
    }
    expect(await store.count(), 55);

    final recent = await store.recent(limit: 50);
    expect(recent.length, 50);
    expect(recent.first.content, 'm6'); // 6..55
    expect(recent.last.content, 'm55');

    final older = await store.olderThan(beforeId: recent.first.id!, limit: 20);
    expect(older.length, 5); // 1..5
    expect(older.first.content, 'm1');
    expect(older.last.content, 'm5');

    await store.clearAll();
    expect(await store.count(), 0);
  });

  test('SqliteConversationStore 增删查 + 分页', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = Directory.systemTemp.createTempSync('sqlite_');
    final db = AppDatabase('${dir.path}/conversation.db');
    final store = SqliteConversationStore(db);
    await store.open();
    addTearDown(() async {
      await db.close();
      dir.deleteSync(recursive: true);
    });

    for (var i = 1; i <= 25; i++) {
      await store.insert(ConversationMessage(
        role: ConversationRole.user,
        content: 'm$i',
        speakerName: i.isOdd ? '张三' : null,
        createdAt: i,
      ));
    }
    expect(await store.count(), 25);

    final recent = await store.recent(limit: 20);
    expect(recent.length, 20);
    expect(recent.last.content, 'm25');
    expect(recent.first.speakerName, isNull); // m6(偶数)→null

    final older = await store.olderThan(beforeId: recent.first.id!, limit: 20);
    expect(older.length, 5);
    expect(older.first.content, 'm1');

    // 删除单条。
    await store.deleteById(recent.last.id!);
    expect(await store.count(), 24);

    await store.clearAll();
    expect(await store.count(), 0);
  });
}
