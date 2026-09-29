/// 短期记忆(STM):当前会话的工作记忆。
///
/// **STM 不是第二份消息存储**。原文只存在 `conversation_messages` 里;
/// STM 是它的**上层压缩视图** —— "最近 N 轮原文"(v1.0.1 已有)加上
/// "更早轮次的滚动摘要"(本服务)。造第二份消息表就是两处真相,必错。
///
/// 两条硬约束:
///
/// 1. **增量摘要**。每轮只把"水位线之后新增的若干条 + 已有摘要"合成新摘要,
///    而不是把整场会话重摘一遍 —— 后者是 O(n²) 的 token 消耗。
///
/// 2. **摘要失败绝不阻塞对话**。LLM 报错/无网/超时一律**静默跳过**,
///    水位线不动,下轮再试。绝不能因为"总结失败"让用户说不下去话。
library;

// 命名参数 + 显式赋值(私有字段不能作命名形参),与 app_dependencies.dart 同约定。
// ignore_for_file: prefer_initializing_formals

import 'package:flutter_tts_demo/data/models/conversation_message.dart';
import 'package:flutter_tts_demo/data/session_memory_store.dart';
import 'package:flutter_tts_demo/utils/llm_client.dart';
import 'package:flutter_tts_demo/utils/llm_service.dart';

class SessionMemoryService {
  SessionMemoryService({
    required SessionMemoryStore store,
    required LlmService llm,
    this.sessionGap = const Duration(minutes: 30),
    this.summarizeBatch = 10,
    this.maxSummaryChars = 200,
  })  : _store = store,
        _llm = llm;

  final SessionMemoryStore _store;
  final LlmService _llm;

  /// 空闲多久算"新的一场会话"。
  ///
  /// 会话边界刻意**不是**"清空历史" —— 那是**删数据**的语义,不该顺带切会话;
  /// 而"停了一会儿再聊"才是自然的边界。
  final Duration sessionGap;

  /// 攒够这么多条未摘要消息才做一次摘要。
  ///
  /// 太勤会浪费 token(几条寒暄不值得总结),太懒则摘要滞后、等于没有。
  final int summarizeBatch;

  /// 摘要长度上限(字)。
  final int maxSummaryChars;

  String? _sessionId;
  int _lastActivityMs = 0;

  String? get currentSessionId => _sessionId;

  /// 取当前会话 id;距上次活动超过 [sessionGap] 则**新开一段**。
  ///
  /// 同时记录本次活动时间(每次对话轮次都应调用)。
  String sessionIdAt(int nowMs) {
    final sid = _sessionId;
    if (sid == null || nowMs - _lastActivityMs > sessionGap.inMilliseconds) {
      _sessionId = 's_$nowMs';
    }
    _lastActivityMs = nowMs;
    return _sessionId!;
  }

  /// 切换/重置会话边界(如用户点"新会话")。
  void reset() {
    _sessionId = null;
    _lastActivityMs = 0;
  }

  /// 读某会话的摘要;失败返回 null(读不到摘要不该影响对话)。
  Future<String?> summaryFor(String sessionId) async {
    try {
      return (await _store.get(sessionId))?.summary;
    } catch (_) {
      return null;
    }
  }

  /// 若该会话攒够了未摘要的消息,做一次**增量**摘要。
  ///
  /// 返回是否真的生成/更新了摘要。**任何失败都返回 false,绝不抛出。**
  Future<bool> maybeSummarize({required String sessionId, int? nowMs}) async {
    try {
      final existing = await _store.get(sessionId);
      final watermark = existing?.summarizedUpToId ?? 0;

      final pending = await _store.countUnsummarized(
        sessionId: sessionId,
        afterId: watermark,
      );
      if (pending < summarizeBatch) return false;

      final batch = await _store.unsummarized(
        sessionId: sessionId,
        afterId: watermark,
        limit: summarizeBatch,
      );
      if (batch.isEmpty) return false;

      final summary = await _summarize(
        previous: existing?.summary,
        messages: batch,
      );
      final trimmed = summary.trim();
      // 空摘要视为失败:写入空摘要会把水位线推过头,那批内容就永远丢了。
      if (trimmed.isEmpty) return false;

      final lastId = batch.last.id;
      if (lastId == null) return false;

      await _store.put(
        sessionId: sessionId,
        summary: trimmed,
        summarizedUpToId: lastId,
        updatedAt: nowMs ?? DateTime.now().millisecondsSinceEpoch,
      );
      return true;
    } catch (_) {
      // 静默跳过:摘要失败绝不能阻塞对话。
      return false;
    }
  }

  Future<void> clearAll() => _store.clearAll();

  /// 调 LLM 合成摘要:把"已有摘要 + 新增对话"合并成一段新摘要。
  Future<String> _summarize({
    String? previous,
    required List<ConversationMessage> messages,
  }) async {
    final transcript = StringBuffer();
    for (final m in messages) {
      final who = m.role == ConversationRole.assistant
          ? '助手'
          : (m.speakerName ?? '未知');
      transcript.writeln('[$who] ${m.content}');
    }

    final user = StringBuffer();
    if (previous != null && previous.trim().isNotEmpty) {
      user.writeln('【已有摘要】');
      user.writeln(previous.trim());
      user.writeln();
      user.writeln('请把上面的摘要与下面的新增对话**合并**成一段新摘要,'
          '不要重复已有内容,也不要丢掉其中的事实。');
    } else {
      user.writeln('请把下面的对话压缩成一段摘要。');
    }
    user.writeln();
    user.writeln('【新增对话】');
    user.write(transcript);

    final out = StringBuffer();
    await for (final delta in _llm.streamChat([
      LlmMessage(role: 'system', content: _summarySystemPrompt),
      LlmMessage(role: 'user', content: user.toString()),
    ])) {
      out.write(delta);
    }
    return out.toString();
  }

  String get _summarySystemPrompt =>
      '你是对话摘要助手。请把对话压缩成一段不超过 $maxSummaryChars 字的中文摘要,'
      '**保留人物、决定、待办与情绪转折**,丢弃寒暄与重复。'
      '多说话人时要点明是谁说的。直接输出摘要正文,不要任何前后缀或标题。';
}
