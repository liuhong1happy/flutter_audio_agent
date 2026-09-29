/// 知识库服务测试(导入 / 后台回填 / 检索 / 降级)。
///
/// 这一组守的是"长任务不毁体验"与"增强能力不拖垮主流程"两类约定:
///  - 导入必须**瞬时**返回(向量留后台补),否则用户要对着转圈等几分钟;
///  - 检索**任何失败都降级为空**,绝不把异常抛给对话流程;
///  - 换嵌入模型必须**自动重建索引**,而不是复用不可比的旧向量。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tts_demo/data/knowledge_store.dart';
import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/utils/memory/knowledge_service.dart';
import 'package:flutter_tts_demo/utils/memory/kb_chunker.dart';

import 'support/fakes.dart';

/// 造一个可直接用的服务:模型视为已就绪(注入假的路径解析器),
/// 嵌入由确定性假引擎完成。
Future<({KnowledgeService service, MemoryKnowledgeStore store, FakeEmbeddingEngine engine, TtsSettings settings})>
    makeService({
  bool modelReady = true,
  bool failOnLoad = false,
  int batchSize = 4,
  KbChunker? chunker,
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  final store = MemoryKnowledgeStore();
  final engine = FakeEmbeddingEngine()..failOnLoad = failOnLoad;
  final settings = TtsSettings();
  await settings.load();

  final service = KnowledgeService(
    store: store,
    settings: settings,
    engine: engine,
    chunker: chunker ?? KbChunker(maxTokens: 40),
    batchSize: batchSize,
    modelFilesResolver: modelReady
        ? () => const EmbeddingModelFiles(
              modelPath: '/fake/model_quantized.onnx',
              tokenizerPath: '/fake/tokenizer.json',
            )
        : () => null,
  );
  return (service: service, store: store, engine: engine, settings: settings);
}

void main() {
  test('导入是**瞬时**的:文本与切块立刻落库,向量留给后台', () async {
    final ctx = await makeService();
    final before = ctx.engine.embedCalls.length;

    final result = await ctx.service.importText(
      autoIndex: false,
      title: '产品手册',
      text: '语音对话系统由离线识别、离线合成与声纹识别三部分组成。' * 6,
    );

    expect(result.chunkCount, greaterThan(1));
    // 导入本身不应触发任何嵌入(嵌入是后台的事)。
    expect(ctx.engine.embedCalls.length, before,
        reason: 'importText 不该同步做嵌入');

    // 列表立刻可见,且进度为 0/N(还没回填)。
    await ctx.service.refresh();
    expect(ctx.service.documents.length, 1);
    final doc = ctx.service.documents.single;
    expect(doc.title, '产品手册');
    expect(doc.chunkCount, result.chunkCount);
    expect(doc.embeddedCount, 0);
    expect(doc.indexProgress, 0);
    expect(doc.isIndexed, isFalse);
  });

  test('后台回填:把待嵌入的块全部补上,进度到 100%', () async {
    final ctx = await makeService();
    await ctx.service.importText(
      autoIndex: false,
      title: 'A',
      text: '语音对话系统由离线识别、离线合成与声纹识别三部分组成。' * 6,
    );
    // 导入时已经 unawaited 启动了回填,这里等它跑完。
    await ctx.service.startBackfill();

    final doc = ctx.service.documents.single;
    expect(doc.embeddedCount, doc.chunkCount);
    expect(doc.isIndexed, isTrue);
    expect(doc.indexProgress, 1.0);
    expect(ctx.service.pendingChunks, 0);
    expect(ctx.engine.isLoaded, isTrue);
  });

  test('回填是**分批**的(受 batchSize 约束,不是一次性全塞)', () async {
    final ctx = await makeService(batchSize: 2);
    await ctx.service.importText(
      autoIndex: false,
      title: 'A',
      text: '这是一句用于测试批量回填的中文内容。' * 20,
    );
    await ctx.service.startBackfill();

    final batches = ctx.engine.embedCalls.where((c) => c.length > 1).length;
    expect(batches, greaterThan(1), reason: '应分成多批,才能边索引边可取消');
    // 除最后一批外,每批不超过 batchSize。
    for (final c in ctx.engine.embedCalls) {
      expect(c.length, lessThanOrEqualTo(2));
    }
  });

  test('检索命中相关块(确定性假引擎:按字符重叠打分)', () async {
    final ctx = await makeService();
    await ctx.service.importText(
      autoIndex: false,
      title: '语音',
      text: '语音对话系统由离线识别与离线合成两部分组成。',
    );
    await ctx.service.importText(
      autoIndex: false,
      title: '食谱',
      text: '红烧肉的做法:五花肉切块,冷水下锅焯水后捞出。',
    );
    await ctx.service.startBackfill();

    final hits = await ctx.service.search('语音对话系统', topK: 1, minScore: 0.0);
    expect(hits, isNotEmpty);
    expect(hits.first.text, contains('语音对话系统'),
        reason: '应命中讲语音的那块,而不是红烧肉');
  });

  test('检索阈值生效:低于阈值的片段不返回', () async {
    final ctx = await makeService();
    await ctx.service.importText(
      autoIndex: false,title: '食谱', text: '红烧肉的做法:五花肉切块焯水。');
    await ctx.service.startBackfill();

    final hit = await ctx.service.search('语音对话系统', topK: 4, minScore: 0.0);
    final withThreshold =
        await ctx.service.search('语音对话系统', topK: 4, minScore: 0.99);
    expect(withThreshold.length, lessThanOrEqualTo(hit.length));
    expect(withThreshold, isEmpty, reason: '阈值 0.99 应把不相关的内容滤掉');
  });

  test('**检索失败降级为空,不抛异常**(绝不打断对话)', () async {
    // 模型不可用(未下载)⇒ ensureEngineLoaded 抛错 ⇒ search 必须吞掉。
    final ctx = await makeService(modelReady: false);
    final hits = await ctx.service.search('任意问题');
    expect(hits, isEmpty);
    expect(ctx.service.lastError, isNotNull);
  });

  test('模型未就绪时后台回填**静默不跑**(不是错误)', () async {
    final ctx = await makeService(modelReady: false);
    await ctx.service.importText(
      autoIndex: false,title: 'A', text: '一些内容足够长以便切块。' * 8);
    await ctx.service.startBackfill();

    expect(ctx.service.isIndexing, isFalse);
    expect(ctx.engine.loadCalls, 0, reason: '模型没下就不该尝试加载');
    // 文档仍在,只是没索引 —— 与"导入成功但索引待办"一致。
    expect(ctx.service.documents.single.isIndexed, isFalse);
  });

  test('**换嵌入模型会自动重建索引**(旧向量不可比,不能复用)', () async {
    final ctx = await makeService();
    await ctx.service.importText(
      autoIndex: false,title: 'A', text: '语音对话系统与声纹识别。' * 6);
    await ctx.service.startBackfill();
    expect(ctx.service.documents.single.isIndexed, isTrue);
    expect(ctx.store.storedModelIds, [kDefaultEmbeddingModelId]);

    // 换到另一个模型:旧向量 model_id 不匹配 ⇒ 应重新变成"待回填"。
    await ctx.settings.setEmbeddingModelId('another-model');
    await ctx.service.refresh();
    expect(ctx.service.documents.single.isIndexed, isFalse,
        reason: '换模型后旧向量必须视为未索引(否则相似度变噪音且不报错)');
    expect(ctx.service.pendingChunks, greaterThan(0));

    await ctx.service.startBackfill();
    expect(ctx.service.documents.single.isIndexed, isTrue);
    expect(ctx.store.storedModelIds.contains('another-model'), isTrue);
  });

  test('坏块被**逐条定位**并报出 id 与长度(否则整批会永远卡住)', () async {
    final ctx = await makeService(batchSize: 4);
    // 先导入,拿到块文本,再把其中一条标记为"嵌入必失败"。
    await ctx.service.importText(
      autoIndex: false,title: 'A', text: '内容一。内容二。内容三。' * 6);
    final pending = await ctx.store.pendingChunks(
      modelId: ctx.service.currentModelId,
      limit: 100,
    );
    expect(pending.length, greaterThan(1));
    ctx.engine.failTexts.add(pending[1].text);

    await ctx.service.startBackfill();

    expect(ctx.service.lastError, isNotNull);
    expect(ctx.service.lastError, contains('块 ${pending[1].id}'),
        reason: '批量报错说不出是哪条,必须逐条重试定位');
    expect(ctx.service.isIndexing, isFalse, reason: '失败后必须退出索引态');
  });

  test('取消回填:已写入的批次保留,下次从缺口继续', () async {
    final ctx = await makeService(batchSize: 1);
    await ctx.service.importText(
      autoIndex: false,title: 'A', text: '内容一。内容二。内容三。' * 20);

    // 在**第 3 批开始前**取消 —— 用钩子而不是靠时序运气。
    ctx.engine.onEmbedCall = (i) {
      if (i == 1) ctx.service.cancelBackfill();
    };
    await ctx.service.startBackfill();

    final total = ctx.service.documents.single.chunkCount;
    final afterCancel = ctx.service.documents.single.embeddedCount;
    expect(afterCancel, greaterThan(0), reason: '取消不该丢掉已写入的批次');
    expect(afterCancel, lessThan(total), reason: '取消后应留有未索引的块');

    // 再次启动:从缺口继续直到全部完成。
    ctx.engine.onEmbedCall = null;
    await ctx.service.startBackfill();
    expect(ctx.service.documents.single.isIndexed, isTrue);
  });

  test('删除文档连带删除其切块(不留检索不到的孤儿数据)', () async {
    final ctx = await makeService();
    final r = await ctx.service.importText(
      autoIndex: false,title: 'A', text: '语音对话系统的内容。' * 6);
    await ctx.service.startBackfill();
    expect(await ctx.store.chunkCount(r.docId), greaterThan(0));

    await ctx.service.deleteDocument(r.docId);

    expect(ctx.service.documents, isEmpty);
    expect(await ctx.store.chunkCount(r.docId), 0);
    final hits = await ctx.service.search('语音对话系统', minScore: 0.0);
    expect(hits, isEmpty, reason: '删掉的文档不该还能被检索到');
  });

  test('清空知识库:文档与切块都没了', () async {
    final ctx = await makeService();
    await ctx.service.importText(
      autoIndex: false,title: 'A', text: '语音对话系统的内容。' * 6);
    await ctx.service.startBackfill();

    await ctx.service.clearAll();

    expect(ctx.service.documents, isEmpty);
    expect(await ctx.service.search('语音对话系统', minScore: 0.0), isEmpty);
  });

  test('嵌入会话可显式释放(常驻内存不小)', () async {
    final ctx = await makeService();
    await ctx.service.importText(
      autoIndex: false,title: 'A', text: '内容足够的文本用于切块。' * 8);
    await ctx.service.startBackfill();
    expect(ctx.service.isEngineLoaded, isTrue);

    await ctx.service.unloadEngine();
    expect(ctx.service.isEngineLoaded, isFalse);
    expect(ctx.engine.unloadCalls, 1);
  });

  test('空文本导入被拒', () async {
    final ctx = await makeService();
    expect(() => ctx.service.importText(
      autoIndex: false,title: 'A', text: '   '),
        throwsArgumentError);
  });
}
