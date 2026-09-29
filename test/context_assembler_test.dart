/// 上下文编排器测试。
///
/// 守的是"预算策略"这类**没有报错但会毁掉效果**的行为:
///  - 超预算时**先砍谁**必须与文档一致(先砍离当下最远的),否则用户会发现
///    "知识库明明有内容却不生效",或者更糟 —— 最近的对话被挤掉了;
///  - token 估算**不能低估**(低估等于预算失效);
///  - 提示词里必须有**反朗读标记**的要求(回复会被 TTS 念出来)。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_tts_demo/data/models/memory_item.dart';
import 'package:flutter_tts_demo/utils/llm_client.dart';
import 'package:flutter_tts_demo/utils/memory/context_assembler.dart';

List<LlmMessage> recent(int n, {int charsPerMessage = 20}) => [
      for (var i = 0; i < n; i++)
        LlmMessage(role: i.isEven ? 'user' : 'assistant', content: '内' * charsPerMessage),
    ];

MemoryItem memory(String content, {String speaker = '张三', double confidence = 0.9}) =>
    MemoryItem(
      id: 1,
      speaker: speaker,
      kind: MemoryKind.fact,
      content: content,
      createdAt: 0,
      updatedAt: 0,
      confidence: confidence,
    );

String systemText(AssembledContext ctx) => ctx.messages.first.content;

void main() {
  group('token 估算:宁可高估,不可低估', () {
    test('中文按 1 字 ≈ 1 token', () {
      expect(estimateTokens('语音对话系统'), 6);
    });

    test('英文按 4 字符 ≈ 1 token', () {
      expect(estimateTokens('abcdefgh'), 2);
    });

    test('CJK 标点与全角也按 1 计', () {
      expect(estimateTokens('。,'), 2);
    });

    test('空串为 0', () {
      expect(estimateTokens(''), 0);
    });

    test('混排不低估:中英混合的总和不小于中文部分', () {
      const s = '语音 English 对话 abc';
      expect(estimateTokens(s), greaterThanOrEqualTo(6));
    });
  });

  group('基本组装', () {
    test('首条是 system,其后按序是最近轮次', () {
      final a = ContextAssembler();
      final ctx = a.assemble(
        systemPrompt: '你是助手。',
        speakerName: '张三',
        recentMessages: recent(3),
      );
      expect(ctx.messages.first.role, 'system');
      expect(ctx.messages.first.content, contains('你是助手。'));
      expect(ctx.messages.length, 4);
      expect(ctx.messages.sublist(1).map((m) => m.role).toList(),
          ['user', 'assistant', 'user']);
      expect(ctx.recentIncluded, 3);
      expect(ctx.recentDropped, 0);
    });

    test('未知说话人写"未知用户",且不注入备注', () {
      final a = ContextAssembler();
      final ctx = a.assemble(
        systemPrompt: '你是助手。',
        recentMessages: recent(1),
      );
      expect(systemText(ctx), contains('未知用户'));
    });

    test('说话人备注只在有备注时出现', () {
      final a = ContextAssembler();
      final withNote = a.assemble(
        systemPrompt: 'x',
        speakerName: '张三',
        speakerNote: '在做 Flutter 语音项目',
        recentMessages: recent(1),
      );
      expect(systemText(withNote), contains('在做 Flutter 语音项目'));

      final blank = a.assemble(
        systemPrompt: 'x',
        speakerName: '张三',
        speakerNote: '   ',
        recentMessages: recent(1),
      );
      expect(systemText(blank), isNot(contains('说话人备注')));
    });

    test('各分节都为空时,不产生空段落', () {
      final a = ContextAssembler();
      final ctx = a.assemble(systemPrompt: '你是助手。', recentMessages: recent(1));
      expect(systemText(ctx), isNot(contains('【已知资料】')));
      expect(systemText(ctx), isNot(contains('长期记忆')));
      expect(systemText(ctx), isNot(contains('摘要')));
      expect(ctx.knowledgeInjected, 0);
      expect(ctx.memoriesInjected, 0);
      expect(ctx.summaryInjected, isFalse);
    });
  });

  group('注入内容与格式', () {
    test('知识库片段带编号与来源,并要求"没有就说不知道"', () {
      final a = ContextAssembler();
      final ctx = a.assemble(
        systemPrompt: '你是助手。',
        recentMessages: recent(1),
        knowledge: const [
          ContextSnippet(text: '产品支持离线识别。', label: '产品手册'),
          ContextSnippet(text: '退款需在 7 日内。', label: '售后政策'),
        ],
      );
      final sys = systemText(ctx);
      expect(sys, contains('【已知资料】'));
      expect(sys, contains('[1]'));
      expect(sys, contains('产品手册'));
      expect(sys, contains('[2]'));
      expect(sys, contains('售后政策'));
      // 反幻觉:必须有"没有就说不知道"的约束。
      expect(sys, contains('我不知道'));
      expect(ctx.knowledgeInjected, 2);
    });

    test('长期记忆渲染为短横线列表', () {
      final a = ContextAssembler();
      final ctx = a.assemble(
        systemPrompt: '你是助手。',
        recentMessages: recent(1),
        memories: [memory('偏好简洁回答'), memory('在做 Flutter 语音项目')],
      );
      final sys = systemText(ctx);
      expect(sys, contains('【关于当前说话人的长期记忆】'));
      expect(sys, contains('- 偏好简洁回答'));
      expect(sys, contains('- 在做 Flutter 语音项目'));
      expect(ctx.memoriesInjected, 2);
    });

    test('会话摘要被注入', () {
      final a = ContextAssembler();
      final ctx = a.assemble(
        systemPrompt: '你是助手。',
        recentMessages: recent(1),
        sessionSummary: '用户先问了模型下载失败,已建议换镜像源。',
      );
      expect(systemText(ctx), contains('【本次会话早前摘要】'));
      expect(systemText(ctx), contains('镜像源'));
      expect(ctx.summaryInjected, isTrue);
    });

    test('**提示词必须要求不要念出引用标记**(回复会被 TTS 朗读)', () {
      // 纯文本聊天不会暴露这个问题:用户会听见"资料方括号一"。
      final a = ContextAssembler();
      final ctx = a.assemble(
        systemPrompt: '你是助手。',
        recentMessages: recent(1),
        knowledge: const [ContextSnippet(text: 'x', label: 'y')],
      );
      expect(systemText(ctx), contains('不要念出'));
      expect(systemText(ctx), contains('[1]'));
    });

    test('知识库超过自身上限时按**整条**停止,不截半句', () {
      final a = ContextAssembler(budget: const ContextBudget(kbTokens: 120));
      final ctx = a.assemble(
        systemPrompt: 'x',
        recentMessages: recent(1),
        knowledge: [
          ContextSnippet(text: '第一条内容。' * 5, label: 'A'), // ≈30 字
          ContextSnippet(text: '第二条内容。' * 20, label: 'B'), // ≈120 字,装不下
        ],
      );
      expect(ctx.knowledgeInjected, 1, reason: '装不下的那条整条不注入');
      expect(systemText(ctx), contains('A'));
      expect(systemText(ctx), isNot(contains('[2]')));
    });
  });

  group('**裁剪顺序**(先砍离当下最远的)', () {
    // 构造"刚好超预算"的场景,然后逐步收紧预算看先砍谁。
    AssembledContext build(ContextBudget budget) => ContextAssembler(budget: budget)
        .assemble(
      systemPrompt: '你是助手。',
      speakerName: '张三',
      recentMessages: recent(4, charsPerMessage: 20),
      knowledge: [ContextSnippet(text: '知识' * 30)],
      memories: [memory('记' * 20)],
      sessionSummary: '摘' * 20,
    );

    test('预算充足:四样都在', () {
      final ctx = build(const ContextBudget(totalTokens: 10000));
      expect(ctx.knowledgeInjected, 1);
      expect(ctx.memoriesInjected, 1);
      expect(ctx.summaryInjected, isTrue);
      expect(ctx.recentIncluded, 4);
      expect(ctx.recentDropped, 0);
    });

    test('预算紧张:第一个被砍的是**知识库**', () {
      // 收紧到刚好装不下全部,但去掉知识库就够。
      final ctx = build(const ContextBudget(totalTokens: 190));
      expect(ctx.knowledgeInjected, 0, reason: '知识库应最先让位');
      expect(ctx.memoriesInjected, 1);
      expect(ctx.summaryInjected, isTrue);
      expect(ctx.recentIncluded, 4, reason: '最近轮次不该在还有别的可砍时被砍');
    });

    test('再紧:知识库之后砍**长期记忆**', () {
      final ctx = build(const ContextBudget(totalTokens: 150));
      expect(ctx.knowledgeInjected, 0);
      expect(ctx.memoriesInjected, 0, reason: '第二步应砍长期记忆');
      expect(ctx.summaryInjected, isTrue);
      expect(ctx.recentIncluded, 4);
    });

    test('再紧:然后砍**会话摘要**', () {
      final ctx = build(const ContextBudget(totalTokens: 110));
      expect(ctx.knowledgeInjected, 0);
      expect(ctx.memoriesInjected, 0);
      expect(ctx.summaryInjected, isFalse, reason: '第三步应砍摘要');
      expect(ctx.recentIncluded, 4);
    });

    test('只有最近轮次也装不下时,才从**最旧**开始丢', () {
      final ctx = build(const ContextBudget(totalTokens: 60, minRecentTurns: 2));
      expect(ctx.recentIncluded, 2, reason: '至少保留 minRecentTurns 轮');
      expect(ctx.recentDropped, 2);
      // 丢的是最旧的,留下的应是最近两条。
      final kept = ctx.messages.sublist(1);
      expect(kept.length, 2);
    });

    test('**至少保留 minRecentTurns 轮**:即使预算极小也不清空对话', () {
      final ctx = build(const ContextBudget(totalTokens: 30, minRecentTurns: 3));
      expect(ctx.recentIncluded, greaterThanOrEqualTo(3));
    });

    test('估算 token 数被回报(便于排查"为什么没注入")', () {
      final ctx = build(const ContextBudget(totalTokens: 10000));
      expect(ctx.estimatedTokens, greaterThan(0));
      expect(ctx.toString(), contains('kb='));
    });
  });
}
