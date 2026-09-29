/// 应用 SQLite 库的**唯一持有者**。
///
/// 为什么要有这个类:会话历史(v1.0.1)、知识库与记忆(v1.0.2)共用**同一个数据库文件**,
/// 而表结构迁移必须**只有一处**(否则各 store 各开连接、各自 `onUpgrade`,
/// 迁移顺序与版本号会打架)。故由本类独占 `openDatabase` 与全部 `CREATE TABLE` /
/// `ALTER TABLE`,各 store 只拿它暴露的 [db] 做读写。
///
/// 迁移铁律:**只增不改不删**。历史数据必须在升级时无缝保留 —— 迁移里只允许
/// `CREATE TABLE` / `CREATE INDEX` / `ALTER TABLE ADD COLUMN`(并回填默认值)。
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase(this._path);

  final String _path;
  Database? _db;

  /// 当前表结构版本。**结构变更时 +1,并在 [_migrations] 注册对应步骤。**
  static const int version = 2;

  Database get db {
    final d = _db;
    if (d == null) throw StateError('AppDatabase 尚未 open()');
    return d;
  }

  bool get isOpen => _db != null;

  Future<void> open() async {
    if (_db != null) return;
    await Directory(p.dirname(_path)).create(recursive: true);
    _db = await openDatabase(
      _path,
      version: version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // ── 建表(全新安装)────────────────────────────────────────────────

  Future<void> _onCreate(Database db, int version) async {
    await _createConversationMessages(db);
    await _migrateToV2(db);
  }

  /// v1:会话历史(单一时间线,不分说话人桶)。
  Future<void> _createConversationMessages(Database db) async {
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

  // ── 版本化迁移(老库升级)──────────────────────────────────────────

  /// 按序执行 `(oldVersion, newVersion]` 之间的迁移步骤。
  ///
  /// 新增字段/表时,在这里追加 `newVersion -> 迁移函数`,即可无缝升级且不丢历史。
  static const Map<int, Future<void> Function(Database db)> _migrations = {
    2: _migrateToV2,
  };

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    for (var v = oldVersion + 1; v <= newVersion; v++) {
      final migrate = _migrations[v];
      if (migrate != null) await migrate(db);
    }
  }

  /// v2:知识库 + 长期记忆 + 会话摘要(v1.0.2)。
  ///
  /// 全部是**新增表**与**新增列**,不动既有数据。
  static Future<void> _migrateToV2(Database db) async {
    // ── 会话分段:摘要需要知道"这段话属于哪一场会话" ──
    // 老数据回填为 'legacy':它们是引入分段概念之前的历史,归一场即可,
    // 不假装知道当时的会话边界。
    await db.execute(
      "ALTER TABLE conversation_messages ADD COLUMN session_id TEXT",
    );
    await db.execute(
      "UPDATE conversation_messages SET session_id = 'legacy' "
      'WHERE session_id IS NULL',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_msg_session '
      'ON conversation_messages(session_id, id)',
    );

    // ── 会话摘要(短期记忆的压缩层)──
    // `summarized_up_to_id` 是**水位线**:只摘要 id 大于它的消息,保证增量
    // (全量重摘要是 O(n²) 的 token 消耗)。
    await db.execute('''
      CREATE TABLE IF NOT EXISTS session_summaries (
        session_id TEXT PRIMARY KEY,
        summary TEXT NOT NULL,
        summarized_up_to_id INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // ── 知识库:文档与切块 ──
    // **不存 embedded_count**:索引进度要相对"当前嵌入模型"才有意义,
    // 存成列会在换模型后失真(旧列仍显示已索引,而实际需要重建)。
    // 改为一条聚合查询按当前模型实时算(见 KnowledgeStore.documents)。
    await db.execute('''
      CREATE TABLE IF NOT EXISTS kb_documents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        source_path TEXT,
        imported_at INTEGER NOT NULL,
        char_count INTEGER NOT NULL,
        chunk_count INTEGER NOT NULL
      )
    ''');
    // `embedding` 可空是**核心设计**:支持"导入瞬时完成、向量后台回填"。
    // 检索只取 embedding 非空的块 ⇒ 未索引完的文档部分可检索。
    // `model_id` 不可省:换嵌入模型后新旧向量不可比,而两者维度相同 ⇒
    // 混用**不报错**,只让排序变噪音(与 v1.0.1 两个声纹模型同类的静默错误)。
    await db.execute('''
      CREATE TABLE IF NOT EXISTS kb_chunks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        doc_id INTEGER NOT NULL,
        seq INTEGER NOT NULL,
        text TEXT NOT NULL,
        embedding BLOB,
        dim INTEGER,
        model_id TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_kb_chunks_doc ON kb_chunks(doc_id)',
    );
    // 部分索引:回填任务每次只扫"还没嵌入的块"。
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_kb_chunks_pending '
      'ON kb_chunks(doc_id) WHERE embedding IS NULL',
    );

    // ── 长期记忆:跨会话的、挂说话人的事实 ──
    await db.execute('''
      CREATE TABLE IF NOT EXISTS memories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        speaker TEXT NOT NULL,
        kind TEXT NOT NULL,
        content TEXT NOT NULL,
        embedding BLOB,
        dim INTEGER,
        model_id TEXT,
        confidence REAL NOT NULL DEFAULT 0.7,
        source_msg_id INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_memories_speaker ON memories(speaker)',
    );
  }
}
