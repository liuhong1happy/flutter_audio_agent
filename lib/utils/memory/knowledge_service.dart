/// 本地知识库服务:导入 → 切块 → 后台回填向量 → 检索。
///
/// 三条设计取舍(都是为了让"长任务"不毁掉体验):
///
/// 1. **导入是瞬时的**。同步只做"切块 + 落文本",向量留空。
///    用户立刻在列表里看到文档,并看到"索引中 3/12"这样的进度,
///    而不是对着转圈对话框等几分钟。
///
/// 2. **回填在后台、可取消、可续**。每批 [batchSize] 块一次前向,
///    中途被杀进程/取消后,下次只补还没嵌入的块(判据见 [KnowledgeStore.pendingChunks])。
///
/// 3. **检索失败一律降级为"不注入",绝不打断对话**。知识库是增强,
///    它的故障不该让用户说不下去话(与门禁拒绝语"不卡死对话"同一原则)。
// 命名参数 + 显式赋值(私有字段不能作命名形参),与 app_dependencies.dart 同约定。
// ignore_for_file: prefer_initializing_formals
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter_tts_demo/data/knowledge_store.dart';
import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/data/model_manager.dart';
import 'package:flutter_tts_demo/data/models/kb_document.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/utils/memory/embedding_engine.dart';
import 'package:flutter_tts_demo/utils/memory/kb_chunker.dart';
import 'package:flutter_tts_demo/utils/memory/vector_store.dart';

/// 导入结果。
class KbImportResult {
  const KbImportResult({required this.docId, required this.chunkCount});

  final int docId;
  final int chunkCount;

  @override
  String toString() => 'KbImportResult(doc=$docId, $chunkCount 块)';
}

/// 嵌入模型的两个文件路径(引擎加载所需)。
class EmbeddingModelFiles {
  const EmbeddingModelFiles({
    required this.modelPath,
    required this.tokenizerPath,
  });

  final String modelPath;
  final String tokenizerPath;
}

class KnowledgeService extends ChangeNotifier {
  KnowledgeService({
    required KnowledgeStore store,
    ModelManager? modelManager,
    required TtsSettings settings,
    KbChunker? chunker,
    EmbeddingEngine? engine,
    int batchSize = 8,
    EmbeddingModelFiles? Function()? modelFilesResolver,
  })  : _store = store,
        _modelManager = modelManager,
        _settings = settings,
        _chunker = chunker ?? KbChunker(),
        _engine = engine ?? FlutterEmbedderEngine(),
        _batchSize = batchSize,
        _modelFilesResolver = modelFilesResolver;

  final KnowledgeStore _store;
  /// 生产环境必传;测试注入 [EmbeddingModelFiles] 解析器时可为 null。
  final ModelManager? _modelManager;
  final TtsSettings _settings;
  final KbChunker _chunker;
  final EmbeddingEngine _engine;
  final int _batchSize;

  /// 测试注入口;为 null 时走 [ModelManager] 解析真实模型路径。
  final EmbeddingModelFiles? Function()? _modelFilesResolver;

  List<KbDocument> _documents = const [];
  List<KbDocument> get documents => _documents;

  bool _indexing = false;
  bool get isIndexing => _indexing;

  int _indexedThisRun = 0;
  int get indexedThisRun => _indexedThisRun;

  String? _lastError;
  String? get lastError => _lastError;

  bool _cancelRequested = false;

  /// 当前生效的嵌入模型 id(设置里没选就用默认)。
  String get currentModelId =>
      _settings.embeddingModelId ?? kDefaultEmbeddingModelId;

  /// 待索引的块数(相对当前模型)。
  int get pendingChunks {
    var total = 0, embedded = 0;
    for (final d in _documents) {
      total += d.chunkCount;
      embedded += d.embeddedCount;
    }
    return total - embedded;
  }

  /// 当前嵌入模型的两个文件路径;不可用(未下载/不完整)时为 null。
  EmbeddingModelFiles? _resolveModelFiles() {
    final injected = _modelFilesResolver;
    if (injected != null) return injected();
    final mm = _modelManager;
    if (mm == null) return null;
    final m = ModelCatalog.byId(currentModelId);
    if (m == null) return null;
    if (!mm.isDownloaded(m.id)) return null;
    final paths = mm.resolveModel(m);
    if (paths == null ||
        !paths.isComplete ||
        paths.modelPath == null ||
        paths.tokenizerJsonPath == null) {
      return null;
    }
    return EmbeddingModelFiles(
      modelPath: paths.modelPath!,
      tokenizerPath: paths.tokenizerJsonPath!,
    );
  }

  /// 嵌入模型是否已下载完整(检索/回填的前置)。
  bool get isModelReady => _resolveModelFiles() != null;

  /// 是否已建立嵌入会话(常驻内存,空闲时应 [unloadEngine])。
  bool get isEngineLoaded => _engine.isLoaded;

  // ── 文档 ────────────────────────────────────────────────────────────

  /// 重新读取文档列表(含按当前模型算出的索引进度)。
  Future<void> refresh() async {
    _documents = await _store.documents(modelId: currentModelId);
    notifyListeners();
  }

  /// 导入一段文本。
  ///
  /// **只做同步的切块 + 落库**;向量交给 [startBackfill] 后台补。
  ///
  /// [autoIndex] 为 true 时导入后**不阻塞地**触发一次回填。
  /// 批量导入多个文件时应传 false,全部导完再调一次 [startBackfill] ——
  /// 否则每个文件各起一轮,批次会被切碎(而且每轮都要重新取一遍待办)。
  Future<KbImportResult> importText({
    required String title,
    required String text,
    String? sourcePath,
    bool autoIndex = true,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('文本为空,无法导入');
    }
    final chunks = _chunker.chunk(trimmed);
    if (chunks.isEmpty) {
      throw ArgumentError('切不出任何有效块,请检查内容');
    }

    final docId = await _store.insertDocument(
      title: title.trim().isEmpty ? '未命名文档' : title.trim(),
      sourcePath: sourcePath,
      charCount: trimmed.length,
      chunkCount: chunks.length,
      importedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _store.insertChunks(docId, chunks.map((c) => c.text).toList());
    _lastError = null;
    await refresh();

    // 不阻塞导入:后台开始回填。
    if (autoIndex) unawaited(startBackfill());

    return KbImportResult(docId: docId, chunkCount: chunks.length);
  }

  Future<void> deleteDocument(int docId) async {
    await _store.deleteDocument(docId);
    await refresh();
  }

  Future<void> clearAll() async {
    await _store.clearAll();
    await refresh();
  }

  // ── 嵌入会话 ────────────────────────────────────────────────────────

  /// 确保嵌入会话就绪。失败时抛错(上层可选择降级为"不检索")。
  Future<void> ensureEngineLoaded() async {
    if (_engine.isLoaded) return;
    final files = _resolveModelFiles();
    if (files == null) {
      throw StateError('嵌入模型未下载完整,请先在「设置 → 知识库」下载模型');
    }
    await _engine.load(
      modelPath: files.modelPath,
      tokenizerPath: files.tokenizerPath,
    );
  }

  /// 释放嵌入会话(常驻内存不小:ONNX 会话 + 95MB Rust 库)。
  Future<void> unloadEngine() async {
    await _engine.unload();
    notifyListeners();
  }

  // ── 后台回填 ────────────────────────────────────────────────────────

  /// 正在跑的回填任务;没有则为 null。
  Future<void>? _backfill;

  /// 开始回填。
  ///
  /// **幂等且可等待**:已在跑时返回**同一个** Future,所以
  /// `await startBackfill()` 总能等到"这一刻的索引工作全部结束",
  /// 而不会在别人正在跑时立刻返回(那会让调用方以为索引完了)。
  ///
  /// 模型未就绪时静默返回 —— 这不是错误,用户可能只是还没下模型。
  Future<void> startBackfill() {
    final running = _backfill;
    if (running != null) return running;
    if (!isModelReady) return Future<void>.value();
    final f = _runBackfill();
    _backfill = f;
    return f;
  }

  Future<void> _runBackfill() async {
    _indexing = true;
    _cancelRequested = false;
    notifyListeners();

    try {
      await ensureEngineLoaded();
      while (!_cancelRequested) {
        final pending = await _store.pendingChunks(
          modelId: currentModelId,
          limit: _batchSize,
        );
        if (pending.isEmpty) break;

        final vecs = await _embedWithDiagnosis(pending);
        await _store.storeEmbeddings(
          modelId: currentModelId,
          items: [
            for (var i = 0; i < pending.length; i++) (pending[i].id, vecs[i]),
          ],
        );
        _indexedThisRun += pending.length;
        await refresh();
      }
      _lastError = null;
    } catch (e) {
      _lastError = '$e';
    } finally {
      _indexing = false;
      _backfill = null;
      notifyListeners();
    }
  }

  /// 取消回填(已写入的批次保留,下次从缺口继续)。
  void cancelBackfill() {
    _cancelRequested = true;
  }

  /// 嵌入一批;整批失败时**逐条重试以定位是哪个块**。
  ///
  /// 为什么值得这么做:批量报错说不出是哪一条出错,而只要有一条坏块(例如超出
  /// 模型长度上限),整个索引就会永远卡在同一批上。逐条重试能把 id 和长度报出来。
  Future<List<Float32List>> _embedWithDiagnosis(List<PendingChunk> pending) async {
    final texts = pending.map((p) => p.text).toList();
    try {
      return await _engine.embed(texts);
    } catch (batchError) {
      if (texts.length == 1) {
        throw StateError(
          '块 ${pending.first.id} 嵌入失败(${texts.first.length} 字): $batchError',
        );
      }
      final out = <Float32List>[];
      for (var i = 0; i < pending.length; i++) {
        try {
          out.add((await _engine.embed([texts[i]])).first);
        } catch (e) {
          throw StateError(
            '块 ${pending[i].id} 嵌入失败(${texts[i].length} 字): $e',
          );
        }
      }
      return out;
    }
  }

  // ── 检索 ────────────────────────────────────────────────────────────

  /// 检索最相关的片段。
  ///
  /// **任何失败都返回空列表**(并记 [lastError]),不抛出 ——
  /// 调用方(对话编排)据此"检索不到就不注入",对话照常进行。
  Future<List<VectorHit>> search(
    String query, {
    int? topK,
    double? minScore,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      await ensureEngineLoaded();
      final queryVec = (await _engine.embed([q])).first;
      final candidates = await _store.loadCandidates(modelId: currentModelId);
      if (candidates.isEmpty) return const [];
      return searchTopK(
        queryVec,
        candidates,
        topK: topK ?? _settings.kbTopK,
        minScore: minScore ?? _settings.kbScoreThreshold,
      );
    } catch (e) {
      _lastError = '$e';
      notifyListeners();
      return const [];
    }
  }
}
