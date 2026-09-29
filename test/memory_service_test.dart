/// 长期记忆(LTM)测试。
///
/// 最要紧的一条是**跨人隔离**:未知说话人既不抽取也不注入。
/// 把张三的记忆注入给陌生人,听起来会非常自然,因而极难察觉 ——
/// 这类错误必须靠测试守住,不能靠"看代码时想起来"。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tts_demo/data/memory_store.dart';
import 'package:flutter_tts_demo/data/models/conversation_message.dart';
import 'package:flutter_tts_demo/data/models/memory_item.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/utils/llm_service.dart';
import 'package:flutter_tts_demo/utils/memory/memory_service.dart';

import 'support/fakes.dart';

const String kModel = 'embed-model';

Future<({MemoryService service, MemoryMemoryStore store, FakeLlmClient llm, FakeEmbeddingEngine engine})>
    makeService({List<String> reply = const ['[]'], bool loadEngine = true}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  final store = MemoryMemoryStore();
  final client = FakeLlmClient(chunks: reply);
  final settings = TtsSettings();
  await settings.setLlmApiKey('test-key');

  final engine = FakeEmbeddingEngine();
  if (loadEngine) {
    await engine.load(modelPath: '/x.onnx', tokenizerPath: '/x.json');
  }

  final service = MemoryService(
    store: store,
    llm: LlmService(settings: settings, client: client),
    currentModelId: () => kModel,
    engine: engine,
    extractEveryTurns: 2,
  );
  return (service: service, store: store, llm: client, engine: engine);
}

List<ConversationMessage> turns(List<(String, String)> pairs) => [
      for (var i = 0; i < pairs.length; i++)
        ConversationMessage(
          id: i + 1,
          role: pairs[i].$1 == 'user'
              ? ConversationRole.user
              : ConversationRole.assistant,
          content: pairs[i].$2,
          speakerName: pairs[i].$1 == 'user' ? '张三' : null,
          createdAt: i,
        ),
    ];

void main() {
  group('未知说话人:**零抽取、零注入**(跨人泄漏防线)', () {
    test('speaker 为空时不抽取,且**根本不调 LLM**', () async {
      final ctx = await makeService();
      final n = await ctx.service.extractFrom(
        speaker: null,
        recentMessages: turns([('user', '我住在北京')]),
      );
      expect(n, 0);
      expect(ctx.llm.capturedMessages, isEmpty, reason: '连 LLM 都不该调用');
    });

    test('speaker 为空白字符串时同样不抽取', () async {
      final ctx = await makeService();
      final n = await ctx.service.extractFrom(
        speaker: '   ',
        recentMessages: turns([('user', '我住在北京')]),
      );
      expect(n, 0);
      expect(ctx.llm.capturedMessages, isEmpty);
    });

    test('speaker 为空时检索返回空(即使用户库里真有记忆)', () async {
      final ctx = await makeService();
      // 先给张三记一条并嵌入。
      await ctx.service.remember(speaker: '张三', content: '喜欢咖啡');

      final hits = await ctx.service.retrieve(
        speaker: null,
        query: '我喜欢喝什么',
      );
      expect(hits, isEmpty, reason: '未知说话人绝不能拿到别人的记忆');
    });

    test('手动「记住这条」在未知说话人下不写入', () async {
      final ctx = await makeService();
      expect(await ctx.service.remember(speaker: null, content: 'x'), isNull);
      expect(await ctx.service.remember(speaker: '  ', content: 'x'), isNull);
      expect(await ctx.store.bySpeaker('张三'), isEmpty);
    });
  });

  group('抽取(LLM)', () {
    test('ADD:把抽到的事实落库到该说话人', () async {
      final ctx = await makeService(
        reply: ['[{"op":"ADD","kind":"preference","content":"偏好简洁回答","confidence":0.9}]'],
      );
      final n = await ctx.service.extractFrom(
        speaker: '张三',
        recentMessages: turns([('user', '以后回答简短点'), ('assistant', '好的')]),
      );
      expect(n, 1);
      final items = await ctx.service.listFor('张三');
      expect(items.single.content, '偏好简洁回答');
      expect(items.single.kind, MemoryKind.preference);
    });

    test('UPDATE:按 id 合并已有记忆(而不是新增一条)', () async {
      final ctx = await makeService();
      final id = await ctx.service.remember(speaker: '张三', content: '在减肥');

      ctx.llm.responder = (_) => [
            '[{"op":"UPDATE","id":$id,"kind":"fact","content":"已停止减肥","confidence":0.9}]',
          ];
      final n = await ctx.service.extractFrom(
        speaker: '张三',
        recentMessages: turns([('user', '不减了')]),
      );

      expect(n, 1);
      final items = await ctx.service.listFor('张三');
      expect(items.length, 1, reason: 'UPDATE 不该新增条目');
      expect(items.single.content, '已停止减肥');
    });

    test('NONE:不落库', () async {
      final ctx = await makeService(reply: ['[{"op":"NONE"}]']);
      final n = await ctx.service.extractFrom(
        speaker: '张三',
        recentMessages: turns([('user', '你好')]),
      );
      expect(n, 0);
      expect(await ctx.service.listFor('张三'), isEmpty);
    });

    test('**抽取前把已有记忆喂给 LLM**(否则会无限膨胀且自相矛盾)', () async {
      final ctx = await makeService(reply: ['[]']);
      await ctx.service.remember(speaker: '张三', content: '喜欢咖啡');

      await ctx.service.extractFrom(
        speaker: '张三',
        recentMessages: turns([('user', '随便聊聊')]),
      );

      final prompt = ctx.llm.capturedMessages.single.last.content;
      expect(prompt, contains('已有记忆'));
      expect(prompt, contains('喜欢咖啡'));
      expect(prompt, contains('id='), reason: '必须给出 id,LLM 才能判 UPDATE');
      expect(prompt, contains('张三'));
    });

    test('提示词要求只抽当前说话人、并支持 ADD/UPDATE/NONE', () async {
      final ctx = await makeService(reply: ['[]']);
      await ctx.service.extractFrom(
        speaker: '张三',
        recentMessages: turns([('user', 'x')]),
      );
      final system = ctx.llm.capturedMessages.single.first.content;
      expect(system, contains('ADD'));
      expect(system, contains('UPDATE'));
      expect(system, contains('NONE'));
      expect(system, contains('当前说话人'));
    });

    test('抽取失败(LLM 抛错)⇒ 返回 0,不抛出', () async {
      final ctx = await makeService();
      ctx.llm.error = '模拟:网络断开';
      final n = await ctx.service.extractFrom(
        speaker: '张三',
        recentMessages: turns([('user', 'x')]),
      );
      expect(n, 0);
      expect(await ctx.service.listFor('张三'), isEmpty);
    });

    test('按轮数触发:攒够 N 轮才该抽取', () async {
      final ctx = await makeService();
      // extractEveryTurns = 2
      expect(ctx.service.shouldExtract, isFalse, reason: '0 轮不该抽取');
      ctx.service.noteTurn();
      expect(ctx.service.shouldExtract, isFalse, reason: '1 轮还不够');
      ctx.service.noteTurn();
      expect(ctx.service.shouldExtract, isTrue, reason: '2 轮应触发');
    });
  });

  group('LLM 输出容错(它会加围栏、加解释、给坏项)', () {
    test('剥 ```json 围栏', () {
      final ops = MemoryService.parseMemoryOps(
        '```json\n[{"op":"ADD","kind":"fact","content":"喜欢猫"}]\n```',
      );
      expect(ops.single.content, '喜欢猫');
    });

    test('前后夹带解释文字也能取出数组', () {
      final ops = MemoryService.parseMemoryOps(
        '好的,这是抽取结果:\n[{"op":"ADD","kind":"fact","content":"住北京"}]\n以上。',
      );
      expect(ops.single.content, '住北京');
    });

    test('单条坏项被丢弃,不影响其余', () {
      final ops = MemoryService.parseMemoryOps(
        '[{"op":"ADD","kind":"fact","content":"好的"},'
        '{"op":"ADD","content":""},'   // 空内容,丢弃
        '{"nope":1},'                    // 缺 op,丢弃
        '{"op":"ADD","kind":"fact","content":"第二条"}]',
      );
      expect(ops.map((o) => o.content).toList(), ['好的', '第二条']);
    });

    test('未知 kind 回落为 fact(不丢数据)', () {
      final ops = MemoryService.parseMemoryOps(
        '[{"op":"ADD","kind":"爱好","content":"钓鱼"}]',
      );
      expect(ops.single.kind, MemoryKind.fact);
    });

    test('confidence 越界被夹紧到 0~1', () {
      final ops = MemoryService.parseMemoryOps(
        '[{"op":"ADD","kind":"fact","content":"a","confidence":5},'
        '{"op":"ADD","kind":"fact","content":"b","confidence":-2}]',
      );
      expect(ops[0].confidence, 1.0);
      expect(ops[1].confidence, 0.0);
    });

    test('非 JSON / 空串 / 没有数组 ⇒ 空列表,不抛', () {
      expect(MemoryService.parseMemoryOps(''), isEmpty);
      expect(MemoryService.parseMemoryOps('抱歉,我无法完成'), isEmpty);
      expect(MemoryService.parseMemoryOps('{not json}'), isEmpty);
      expect(MemoryService.parseMemoryOps('[1,2,3]'), isEmpty);
    });
  });

  group('检索与隔离', () {
    test('按说话人隔离:张三的记忆检索不到李四的', () async {
      final ctx = await makeService();
      await ctx.service.remember(speaker: '张三', content: '喜欢咖啡');
      await ctx.service.remember(speaker: '李四', content: '喜欢喝茶');

      final forZhang = await ctx.service.retrieve(
        speaker: '张三',
        query: '喜欢咖啡',
      );
      expect(forZhang.map((m) => m.content), ['喜欢咖啡']);
      expect(forZhang.map((m) => m.content), isNot(contains('喜欢喝茶')));

      final forLi = await ctx.service.retrieve(speaker: '李四', query: '喜欢喝茶');
      expect(forLi.map((m) => m.content), contains('喜欢喝茶'));
    });

    test('低置信度的记忆**不注入**', () async {
      final ctx = await makeService();
      await ctx.service.remember(
        speaker: '张三',
        content: '可能喜欢咖啡',
        confidence: 0.2, // 低于阈值 0.5
      );
      final hits = await ctx.service.retrieve(speaker: '张三', query: '咖啡');
      expect(hits, isEmpty);
    });

    test('引擎未加载 ⇒ 返回空(不抛)', () async {
      final ctx = await makeService(loadEngine: false);
      await ctx.service.remember(speaker: '张三', content: '喜欢咖啡');
      expect(await ctx.service.retrieve(speaker: '张三', query: '咖啡'), isEmpty);
    });

    test('空查询返回空', () async {
      final ctx = await makeService();
      await ctx.service.remember(speaker: '张三', content: '喜欢咖啡');
      expect(await ctx.service.retrieve(speaker: '张三', query: '  '), isEmpty);
    });
  });

  group('增删', () {
    test('deleteById 删掉单条', () async {
      final ctx = await makeService();
      final id = (await ctx.service.remember(speaker: '张三', content: 'x'))!;
      await ctx.service.deleteById(id);
      expect(await ctx.service.listFor('张三'), isEmpty);
    });

    test('clearSpeaker 只清某个人的', () async {
      final ctx = await makeService();
      await ctx.service.remember(speaker: '张三', content: 'a');
      await ctx.service.remember(speaker: '李四', content: 'b');

      await ctx.service.clearSpeaker('张三');

      expect(await ctx.service.listFor('张三'), isEmpty);
      expect(await ctx.service.listFor('李四'), hasLength(1));
    });

    test('clearAll 清空', () async {
      final ctx = await makeService();
      await ctx.service.remember(speaker: '张三', content: 'a');
      await ctx.service.clearAll();
      expect(await ctx.service.listFor('张三'), isEmpty);
    });

    test('手动记忆默认高置信度(用户显式记的比推断的可信)', () async {
      final ctx = await makeService();
      final id = (await ctx.service.remember(speaker: '张三', content: 'x'))!;
      final items = await ctx.service.listFor('张三');
      expect(items.single.id, id);
      expect(items.single.confidence, greaterThanOrEqualTo(0.5));
    });
  });
}
