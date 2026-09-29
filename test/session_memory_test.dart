/// 短期记忆(会话分段 + 增量摘要)测试。
///
/// 守的两条硬约束:
///  - **增量**:每次摘要只吃"水位线之后的新增条数",不是把整场会话重摘一遍
///    (后者是 O(n²) 的 token 消耗,对话越长越贵);
///  - **失败静默**:LLM 报错/空响应都不能把异常抛给对话流程,也不能把水位线推过头
///    (推过头 = 那批内容永远丢了)。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tts_demo/data/models/conversation_message.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/data/session_memory_store.dart';
import 'package:flutter_tts_demo/utils/llm_service.dart';
import 'package:flutter_tts_demo/utils/memory/session_memory_service.dart';

import 'support/fakes.dart';

const int kMinute = 60 * 1000;

Future<({SessionMemoryService service, MemorySessionMemoryStore store, FakeLlmClient llm})>
    makeService({
  List<String> reply = const ['摘要内容'],
  Duration gap = const Duration(minutes: 30),
  int batch = 3,
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final store = MemorySessionMemoryStore();
  final client = FakeLlmClient(chunks: reply);
  final settings = TtsSettings();
  // LlmService 在无 key 时直接返回错误流 —— 测试必须配一个,否则只会测到'失败静默'。
  await settings.setLlmApiKey('test-key');
  final service = SessionMemoryService(
    store: store,
    llm: LlmService(settings: settings, client: client),
    sessionGap: gap,
    summarizeBatch: batch,
    maxSummaryChars: 200,
  );
  return (service: service, store: store, llm: client);
}

/// 往某会话塞 n 条消息。
void seed(MemorySessionMemoryStore store, String sessionId, int n,
    {String prefix = '内容'}) {
  for (var i = 0; i < n; i++) {
    store.addMessage(sessionId: sessionId, content: '$prefix$i', createdAt: i);
  }
}

void main() {
  group('会话分段', () {
    test('连续活动落在同一段', () async {
      final ctx = await makeService();
      final a = ctx.service.sessionIdAt(0);
      final b = ctx.service.sessionIdAt(5 * kMinute);
      final c = ctx.service.sessionIdAt(20 * kMinute);
      expect(b, a);
      expect(c, a);
    });

    test('空闲超过阈值 ⇒ 新开一段', () async {
      final ctx = await makeService(gap: const Duration(minutes: 30));
      final a = ctx.service.sessionIdAt(0);
      final b = ctx.service.sessionIdAt(31 * kMinute);
      expect(b, isNot(a), reason: '停了一会儿再聊应算新会话');

      // 新段之后又是连续活动 ⇒ 仍在新段里。
      expect(ctx.service.sessionIdAt(32 * kMinute), b);
    });

    test('恰好等于阈值不算新段(边界)', () async {
      final ctx = await makeService(gap: const Duration(minutes: 30));
      final a = ctx.service.sessionIdAt(0);
      expect(ctx.service.sessionIdAt(30 * kMinute), a);
    });

    test('reset 后下一句开新段', () async {
      final ctx = await makeService();
      final a = ctx.service.sessionIdAt(0);
      ctx.service.reset();
      expect(ctx.service.sessionIdAt(1), isNot(a));
    });

    test('会话 id 可比较(带时间戳前缀)', () async {
      final ctx = await makeService();
      final id = ctx.service.sessionIdAt(123456);
      expect(id, contains('123456'));
    });
  });

  group('增量摘要', () {
    test('未攒够阈值 ⇒ 不摘要', () async {
      final ctx = await makeService(batch: 3);
      const sid = 's_1';
      seed(ctx.store, sid, 2);
      expect(await ctx.service.maybeSummarize(sessionId: sid), isFalse);
      expect(ctx.llm.capturedMessages, isEmpty, reason: '不该白白调 LLM');
    });

    test('攒够阈值 ⇒ 摘要写入并推进水位线', () async {
      final ctx = await makeService(batch: 3, reply: ['用户问了下载问题,已建议换镜像。']);
      const sid = 's_1';
      seed(ctx.store, sid, 3);

      expect(await ctx.service.maybeSummarize(sessionId: sid), isTrue);
      final saved = await ctx.store.get(sid);
      expect(saved, isNotNull);
      expect(saved!.summary, contains('镜像'));
      expect(saved.summarizedUpToId, 3, reason: '水位线应推到本批最后一条');
      expect(await ctx.service.summaryFor(sid), contains('镜像'));
    });

    test('**增量**:第二次只吃新增的条数,并把已有摘要一并交给 LLM 合并', () async {
      final ctx = await makeService(batch: 3);
      const sid = 's_1';
      seed(ctx.store, sid, 3, prefix: '第一批');
      await ctx.service.maybeSummarize(sessionId: sid);
      final firstPrompt = ctx.llm.capturedMessages.single.last.content;
      expect(firstPrompt, contains('第一批0'));
      expect(firstPrompt, isNot(contains('【已有摘要】')));

      // 再来 3 条。
      seed(ctx.store, sid, 3, prefix: '第二批');
      // 注意:seed 会从 0 重新编号,所以这里显式改成第 4..6 条的内容。
      ctx.llm.capturedMessages.clear();
      expect(await ctx.service.maybeSummarize(sessionId: sid), isTrue);

      final secondPrompt = ctx.llm.capturedMessages.single.last.content;
      // 新增部分只含第二批,不应把第一批再喂一遍。
      expect(secondPrompt, contains('第二批'), reason: '应包含新增对话');
      expect(
        secondPrompt.contains('第一批0') && secondPrompt.contains('第一批2'),
        isFalse,
        reason: '第一批已被摘要过,不该作为"新增对话"再喂一遍(那就不叫增量了)',
      );
      // 但已有摘要必须一起给 LLM,否则合并会丢事实。
      expect(secondPrompt, contains('【已有摘要】'));
      expect(secondPrompt, contains('摘要内容'));
    });

    test('水位线推进后,同一批不会被重复摘要', () async {
      final ctx = await makeService(batch: 3);
      const sid = 's_1';
      seed(ctx.store, sid, 3);
      expect(await ctx.service.maybeSummarize(sessionId: sid), isTrue);
      ctx.llm.capturedMessages.clear();

      // 没有新消息 ⇒ 不该再摘要。
      expect(await ctx.service.maybeSummarize(sessionId: sid), isFalse);
      expect(ctx.llm.capturedMessages, isEmpty);
    });

    test('多说话人:转录里带说话人标签', () async {
      final ctx = await makeService(batch: 2);
      const sid = 's_1';
      ctx.store.addMessage(sessionId: sid, content: '我喜欢咖啡', speakerName: '张三');
      ctx.store.addMessage(
        sessionId: sid,
        content: '好的',
        role: ConversationRole.assistant,
      );

      await ctx.service.maybeSummarize(sessionId: sid);
      final prompt = ctx.llm.capturedMessages.single.last.content;
      expect(prompt, contains('[张三]'));
      expect(prompt, contains('[助手]'));
    });

    test('摘要提示词要求保留人物/决定/待办并限长', () async {
      final ctx = await makeService(batch: 1);
      ctx.store.addMessage(sessionId: 's_1', content: 'x');
      await ctx.service.maybeSummarize(sessionId: 's_1');
      final system = ctx.llm.capturedMessages.single.first.content;
      expect(system, contains('200'));
      expect(system, contains('人物'));
      expect(system, contains('待办'));
    });
  });

  group('失败一律静默(绝不阻塞对话)', () {
    test('LLM 抛错 ⇒ 返回 false,不抛出,水位线不动', () async {
      final ctx = await makeService(batch: 3);
      const sid = 's_1';
      seed(ctx.store, sid, 3);
      ctx.llm.error = '模拟:网络断开';

      final ok = await ctx.service.maybeSummarize(sessionId: sid);

      expect(ok, isFalse);
      expect(await ctx.store.get(sid), isNull, reason: '失败不该写入水位线');
    });

    test('LLM 返回空 ⇒ 不写入(否则水位线越过了没被摘要的内容)', () async {
      final ctx = await makeService(batch: 3, reply: []);
      const sid = 's_1';
      seed(ctx.store, sid, 3);

      expect(await ctx.service.maybeSummarize(sessionId: sid), isFalse);
      expect(await ctx.store.get(sid), isNull);
    });

    test('LLM 返回空白 ⇒ 同样不写入', () async {
      final ctx = await makeService(batch: 3, reply: ['   \n  ']);
      const sid = 's_1';
      seed(ctx.store, sid, 3);
      expect(await ctx.service.maybeSummarize(sessionId: sid), isFalse);
      expect(await ctx.store.get(sid), isNull);
    });

    test('读摘要失败 ⇒ 返回 null 而不是抛错', () async {
      final ctx = await makeService();
      // 没写过的会话
      expect(await ctx.service.summaryFor('不存在'), isNull);
    });

    test('失败之后仍可继续:下一轮攒够新消息能正常摘要', () async {
      final ctx = await makeService(batch: 3);
      const sid = 's_1';
      seed(ctx.store, sid, 3);
      ctx.llm.error = '模拟:暂时失败';
      expect(await ctx.service.maybeSummarize(sessionId: sid), isFalse);

      // 恢复后重试同一批(水位线没动,所以还是这批)。
      ctx.llm.error = null;
      expect(await ctx.service.maybeSummarize(sessionId: sid), isTrue);
      expect((await ctx.store.get(sid))!.summarizedUpToId, 3);
    });
  });

  test('clearAll 清掉所有摘要', () async {
    final ctx = await makeService(batch: 1);
    seed(ctx.store, 's_1', 1);
    await ctx.service.maybeSummarize(sessionId: 's_1');
    expect(await ctx.service.summaryFor('s_1'), isNotNull);

    await ctx.service.clearAll();
    expect(await ctx.service.summaryFor('s_1'), isNull);
  });
}
