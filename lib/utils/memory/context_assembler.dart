/// 上下文编排器:把「系统提示 + 身份/备注 + 知识库片段 + 长期记忆 + 会话摘要 +
/// 最近若干轮」按**预算**拼成最终的提示词。
///
/// 为什么需要它:v1.0.1 的 `_buildLlmMessages()` 只是"系统提示 + 最近 N 条",
/// 想加东西就直接加,迟早把上下文撑爆。这里把"加什么、最多占多少、超了先砍谁"
/// 变成一处明确定义、可测的策略。
///
/// 预算分配与**裁剪顺序**(先砍离当下最远的):
/// ```
/// 总预算 B(默认 4000 token 估算)
/// ├─ ① 系统提示 / ② 身份+备注      固定,不裁剪
/// ├─ ③ 知识库 top-k                ≤ 1200
/// ├─ ④ 长期记忆 top-k              ≤  600
/// ├─ ⑤ 会话摘要(STM)              ≤  500
/// └─ ⑥ 最近 N 轮原文               剩余,且至少保留最近 4 轮
/// 裁剪:③ KB → ④ LTM → ⑤ 摘要 → ⑥ 最近 N 轮
/// ```
/// 理由:越靠近"此刻这句话"的信息越不可省;知识库是增强,先让位。
library;

import 'dart:math' as math;

import 'package:flutter_tts_demo/data/models/memory_item.dart';
import 'package:flutter_tts_demo/utils/llm_client.dart';

/// 预算配置(token 估算值)。
class ContextBudget {
  const ContextBudget({
    this.totalTokens = 4000,
    this.kbTokens = 1200,
    this.memoryTokens = 600,
    this.summaryTokens = 500,
    this.minRecentTurns = 4,
  });

  final int totalTokens;
  final int kbTokens;
  final int memoryTokens;
  final int summaryTokens;

  /// 无论怎么裁,最近这么多轮必须保留。
  final int minRecentTurns;
}

/// 一段待注入的上下文片段(知识库来源)。
///
/// 刻意不直接用检索的 `VectorHit`:编排器不该知道检索的实现细节,
/// 而"来源标题"这类信息由调用方补(检索层只有 docId)。
class ContextSnippet {
  const ContextSnippet({required this.text, this.label});

  final String text;

  /// 来源标签,如文档标题。
  final String? label;
}

/// 编排结果(带诊断信息,便于"为什么没注入"这类问题定位)。
class AssembledContext {
  const AssembledContext({
    required this.messages,
    required this.estimatedTokens,
    required this.knowledgeInjected,
    required this.memoriesInjected,
    required this.summaryInjected,
    required this.recentIncluded,
    required this.recentDropped,
  });

  final List<LlmMessage> messages;
  final int estimatedTokens;

  final int knowledgeInjected;
  final int memoriesInjected;
  final bool summaryInjected;

  /// 实际纳入的最近轮次数。
  final int recentIncluded;

  /// 因为预算被丢掉的更早轮次数。
  final int recentDropped;

  @override
  String toString() => 'AssembledContext(≈${estimatedTokens}tok, '
      'kb=$knowledgeInjected, mem=$memoriesInjected, '
      'sum=$summaryInjected, recent=$recentIncluded(+丢$recentDropped))';
}

/// 估算 token 数。
///
/// ⚠️ **宁可高估,不可低估**。低估会让预算形同虚设。故:
/// 中日韩字符按 **1 字 = 1 token** 计(实际通常就是 1,不会低估);
/// 其余字符按 4 字符 = 1 token 计(英文的常见比例)。
/// 不引 tokenizer 依赖 —— 预算只需"不超太多",不需要精确。
int estimateTokens(String text) {
  if (text.isEmpty) return 0;
  var cjk = 0;
  var other = 0;
  for (final r in text.runes) {
    if (_isCjk(r)) {
      cjk++;
    } else {
      other++;
    }
  }
  return cjk + (other / 4).ceil();
}

/// CJK 判定(含中文标点与全角形式,它们同样约占 1 token)。
bool _isCjk(int r) {
  return (r >= 0x3000 && r <= 0x303F) || // CJK 标点
      (r >= 0x3400 && r <= 0x4DBF) ||
      (r >= 0x4E00 && r <= 0x9FFF) ||
      (r >= 0xF900 && r <= 0xFAFF) ||
      (r >= 0xFF00 && r <= 0xFFEF) || // 全角
      (r >= 0x20000 && r <= 0x2FA1F);
}

class ContextAssembler {
  ContextAssembler({ContextBudget? budget}) : budget = budget ?? const ContextBudget();

  final ContextBudget budget;

  /// 组装提示词。
  ///
  /// [recentMessages] 应按时间升序(旧→新)。
  AssembledContext assemble({
    required String systemPrompt,
    required List<LlmMessage> recentMessages,
    String? speakerName,
    String? speakerNote,
    List<ContextSnippet> knowledge = const [],
    List<MemoryItem> memories = const [],
    String? sessionSummary,
  }) {
    // ── ①② 固定部分:身份与备注不参与裁剪 ──
    final head = StringBuffer(systemPrompt.trim());
    if (speakerName == null || speakerName.trim().isEmpty) {
      head.write('\n当前说话人: 未知用户');
    } else {
      head.write('\n当前说话人: ${speakerName.trim()}');
      final note = speakerNote?.trim() ?? '';
      if (note.isNotEmpty) head.write('\n说话人备注: $note');
    }
    final headText = head.toString();
    final headTokens = estimateTokens(headText);

    // ── ③④⑤ 可变分节(各自有独立上限)──
    final kbRendered = _renderKnowledge(knowledge, budget.kbTokens);
    final memRendered = _renderMemories(memories, budget.memoryTokens);
    var kbSection = kbRendered.text;
    var memSection = memRendered.text;
    var sumSection = _renderSummary(sessionSummary, budget.summaryTokens);

    // ── ⑥ 最近轮次:按剩余预算从**最旧**开始丢 ──
    var recent = List<LlmMessage>.of(recentMessages);
    final minKeep = math.min(budget.minRecentTurns, recent.length);

    int totalTokens() =>
        headTokens +
        estimateTokens(kbSection) +
        estimateTokens(memSection) +
        estimateTokens(sumSection) +
        _sumTokens(recent);

    // ── 裁剪:先砍离当下最远的 ──
    // 顺序是刻意的,与文件头注释一致;改动它必须同步改测试与文档。
    if (totalTokens() > budget.totalTokens) kbSection = '';
    if (totalTokens() > budget.totalTokens) memSection = '';
    if (totalTokens() > budget.totalTokens) sumSection = '';
    while (totalTokens() > budget.totalTokens && recent.length > minKeep) {
      recent.removeAt(0);
    }
    // ⚠️ **到此为止,不再往下砍**。即使"固定段 + minKeep 轮"本身已超预算,
    // 也保留它们 —— "最近几轮"是对话的不可省部分,超一点预算远好过丢掉对话。
    // (默认 totalTokens=4000 而在线 LLM 的上下文远大于此,这条只在极端配置下才触发。)

    // 拼装:把各分节作为 system 的补充段(而不是塞进最后一条 user,
    // 那样会被用户消息"包住",模型更容易把资料当作用户说的话)。
    final sections = <String>[headText];
    if (kbSection.isNotEmpty) sections.add(kbSection);
    if (memSection.isNotEmpty) sections.add(memSection);
    if (sumSection.isNotEmpty) sections.add(sumSection);
    sections.add(_antiReadoutRule);

    final messages = <LlmMessage>[
      LlmMessage(role: 'system', content: sections.join('\n\n')),
      ...recent,
    ];

    return AssembledContext(
      messages: messages,
      estimatedTokens: headTokens +
          estimateTokens(kbSection) +
          estimateTokens(memSection) +
          estimateTokens(sumSection) +
          _sumTokens(recent),
      knowledgeInjected: kbSection.isEmpty ? 0 : kbRendered.count,
      memoriesInjected: memSection.isEmpty ? 0 : memRendered.count,
      summaryInjected: sumSection.isNotEmpty,
      recentIncluded: recent.length,
      recentDropped: math.max(0, recentMessages.length - recent.length),
    );
  }

  static int _sumTokens(List<LlmMessage> msgs) {
    var n = 0;
    for (final m in msgs) {
      n += estimateTokens(m.content);
    }
    return n;
  }

  /// ⚠️ **给 TTS 场景的专属约束**:回复会被**朗读**出来。
  /// 若模型回答"根据资料[1]……",用户会听见"资料方括号一"。
  /// 文本聊天里根本不会暴露这个问题。
  static const String _antiReadoutRule =
      '回答要求:直接给出答案,不要念出"[1]"这类编号或来源说明,'
      '也不要复述本段说明本身。';

  /// ③ 知识库片段。带上"没有就说不知道"的反幻觉约束。
  ({String text, int count}) _renderKnowledge(
      List<ContextSnippet> snippets, int tokenCap) {
    if (snippets.isEmpty) return (text: '', count: 0);
    final buf = StringBuffer(
      '【已知资料】以下内容来自用户的知识库,仅供回答参考。'
      '若资料中没有答案,请明确说"我不知道",不要编造。',
    );
    var used = estimateTokens(buf.toString());
    var i = 0;
    for (final s in snippets) {
      final label = (s.label?.trim().isNotEmpty ?? false) ? ' 来源:《${s.label!.trim()}》' : '';
      final body = s.text.trim();
      if (body.isEmpty) continue;
      final line = '\n[${i + 1}]$label\n$body';
      final cost = estimateTokens(line);
      if (used + cost > tokenCap) break; // 到上限就停(不截断正文,避免半句话)
      buf.write(line);
      used += cost;
      i++;
    }
    return (text: i == 0 ? '' : buf.toString(), count: i);
  }

  /// ④ 长期记忆(已按说话人过滤、已按相关度排序)。
  ({String text, int count}) _renderMemories(
      List<MemoryItem> memories, int tokenCap) {
    if (memories.isEmpty) return (text: '', count: 0);
    final buf = StringBuffer('【关于当前说话人的长期记忆】');
    var used = estimateTokens(buf.toString());
    var i = 0;
    for (final m in memories) {
      final body = m.content.trim();
      if (body.isEmpty) continue;
      final line = '\n- $body';
      final cost = estimateTokens(line);
      if (used + cost > tokenCap) break;
      buf.write(line);
      used += cost;
      i++;
    }
    return (text: i == 0 ? '' : buf.toString(), count: i);
  }

  /// ⑤ 会话摘要(短期记忆的压缩层)。
  String _renderSummary(String? summary, int tokenCap) {
    final text = summary?.trim() ?? '';
    if (text.isEmpty) return '';
    final header = '【本次会话早前摘要】\n';
    final room = tokenCap - estimateTokens(header);
    if (room <= 0) return '';
    // 超长则截断(摘要是我们自己生成的,截断比整段丢弃更划算)。
    var body = text;
    if (estimateTokens(body) > room) {
      // 按字符粗裁:估算按 CJK 1:1,故直接按 room 截字符数是安全的保守做法。
      body = '${body.substring(0, math.min(body.length, room))}…';
    }
    return '$header$body';
  }
}
