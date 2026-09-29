/// 长期记忆(LTM):跨会话成立、**挂在说话人身上**的事实。
///
/// 与短期记忆的分工:STM 回答"这场对话刚才说到哪了";LTM 回答"关于这个人,
/// 我知道什么事实"。前者随会话结束失效,后者永久(可删)。
///
/// 关键取舍:
///
/// 1. **未知说话人零抽取、零注入**(硬约束)。与 v1.0.1 的访客模式一致;
///    否则把张三的记忆注入给陌生人,就是**跨人信息泄漏** ——
///    而且听起来极自然、极难察觉。判据看**当前识别结果**,不看"库里有谁的记忆"。
///
/// 2. **抽取前必须把已有记忆一起给 LLM**,让它判定 ADD/UPDATE/NONE。
///    没有这一步,记忆库会无限膨胀且自相矛盾(三个月后会有五条"用户在减肥"
///    和三条互相冲突的饮食偏好)。
///
/// 3. **抽取失败一律静默跳过**。记忆是增强,不能因为提炼失败打断对话。
// 命名参数 + 显式赋值(私有字段不能作命名形参),与 app_dependencies.dart 同约定。
// ignore_for_file: prefer_initializing_formals
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:flutter_tts_demo/data/memory_store.dart';
import 'package:flutter_tts_demo/data/models/conversation_message.dart';
import 'package:flutter_tts_demo/data/models/memory_item.dart';
import 'package:flutter_tts_demo/utils/llm_client.dart';
import 'package:flutter_tts_demo/utils/llm_service.dart';
import 'package:flutter_tts_demo/utils/memory/embedding_engine.dart';
import 'package:flutter_tts_demo/utils/memory/vector_store.dart';

/// 抽取出的一个操作。
class MemoryOp {
  const MemoryOp({
    required this.op,
    required this.kind,
    required this.content,
    this.id,
    this.confidence = 0.7,
  });

  final String op; // ADD | UPDATE | NONE
  final String kind;
  final String content;
  final int? id;
  final double confidence;

  @override
  String toString() => 'MemoryOp($op, id=$id, $kind, $content)';
}

class MemoryService extends ChangeNotifier {
  MemoryService({
    required MemoryStore store,
    required LlmService llm,
    required String Function() currentModelId,
    EmbeddingEngine? engine,
    int extractEveryTurns = 4,
    double minConfidence = 0.5,
  })  : _store = store,
        _llm = llm,
        _currentModelId = currentModelId,
        _engine = engine,
        _extractEveryTurns = extractEveryTurns,
        _minConfidence = minConfidence;

  final MemoryStore _store;
  final LlmService _llm;
  final String Function() _currentModelId;
  final EmbeddingEngine? _engine;

  /// 每攒够这么多轮做一次抽取(单轮上下文往往推不出稳定事实)。
  final int _extractEveryTurns;

  /// 低于此置信度的记忆**不注入**提示词。
  final double _minConfidence;

  String? _lastError;
  String? get lastError => _lastError;

  int _turnsSinceExtract = 0;

  /// 记一轮对话(用于按轮数触发抽取)。
  void noteTurn() => _turnsSinceExtract++;

  bool get shouldExtract => _turnsSinceExtract >= _extractEveryTurns;

  // ── 读写 ────────────────────────────────────────────────────────────

  /// 手动记一条(对话页"记住这条"用它,跳过 LLM 抽取)。
  ///
  /// 未知说话人**不记** —— 没有归属的记忆无法隔离。
  Future<int?> remember({
    required String? speaker,
    required String content,
    String kind = MemoryKind.fact,
    int? sourceMsgId,
    double confidence = 0.9,
  }) async {
    final who = speaker?.trim() ?? '';
    final text = content.trim();
    if (who.isEmpty || text.isEmpty) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await _store.insert(
      speaker: who,
      kind: kind,
      content: text,
      createdAt: now,
      updatedAt: now,
      confidence: confidence,
      sourceMsgId: sourceMsgId,
    );
    await _embedPending();
    notifyListeners();
    return id;
  }

  Future<List<MemoryItem>> listFor(String speaker) => _store.bySpeaker(speaker);

  Future<void> deleteById(int id) async {
    await _store.deleteById(id);
    notifyListeners();
  }

  Future<void> clearSpeaker(String speaker) async {
    await _store.clearSpeaker(speaker);
    notifyListeners();
  }

  Future<void> clearAll() async {
    await _store.clearAll();
    notifyListeners();
  }

  // ── 检索(注入用)────────────────────────────────────────────────────

  /// 取与 [query] 最相关的该说话人记忆。
  ///
  /// **未知说话人([speaker] 为空)一律返回空** —— 见文件头第 1 点。
  /// 任何失败也返回空(不注入),绝不打断对话。
  Future<List<MemoryItem>> retrieve({
    required String? speaker,
    required String query,
    int topK = 6,
  }) async {
    final who = speaker?.trim() ?? '';
    if (who.isEmpty) return const [];
    final q = query.trim();
    if (q.isEmpty) return const [];
    final engine = _engine;
    if (engine == null || !engine.isLoaded) return const [];

    try {
      final queryVec = (await engine.embed([q])).first;
      final candidates = await _store.loadCandidates(
        modelId: _currentModelId(),
        speaker: who,
      );
      if (candidates.isEmpty) return const [];
      final hits = searchTopK(queryVec, candidates, topK: topK);
      final byId = {for (final m in await _store.bySpeaker(who)) m.id: m};
      final out = <MemoryItem>[];
      for (final h in hits) {
        final m = byId[h.id];
        if (m == null) continue;
        // 低置信度的不注入:宁可少记,不可乱记。
        if (m.confidence < _minConfidence) continue;
        out.add(m);
      }
      return out;
    } catch (e) {
      _lastError = '$e';
      return const [];
    }
  }

  // ── 抽取(LLM)───────────────────────────────────────────────────────

  /// 从最近若干轮里抽取该说话人的长期记忆。
  ///
  /// 返回本次落库的条数(ADD + UPDATE)。**任何失败都返回 0,不抛出。**
  Future<int> extractFrom({
    required String? speaker,
    required List<ConversationMessage> recentMessages,
  }) async {
    final who = speaker?.trim() ?? '';
    if (who.isEmpty) return 0; // 未知说话人不抽取(硬约束)
    if (recentMessages.isEmpty) return 0;

    try {
      final existing = await _store.bySpeaker(who);
      final ops = await _askForOps(
        speaker: who,
        messages: recentMessages,
        existing: existing,
      );
      if (ops.isEmpty) {
        _turnsSinceExtract = 0;
        return 0;
      }

      final byId = {for (final m in existing) m.id: m};
      final now = DateTime.now().millisecondsSinceEpoch;
      var applied = 0;

      for (final op in ops) {
        // 逐条 try/catch:单条坏数据不能毁整批。
        try {
          switch (op.op) {
            case 'ADD':
              if (op.content.trim().isEmpty) continue;
              await _store.insert(
                speaker: who,
                kind: op.kind,
                content: op.content.trim(),
                createdAt: now,
                updatedAt: now,
                confidence: op.confidence,
              );
              applied++;
            case 'UPDATE':
              final target = op.id == null ? null : byId[op.id];
              if (target == null || op.content.trim().isEmpty) continue;
              await _store.updateContent(
                target.id,
                kind: op.kind,
                content: op.content.trim(),
                confidence: op.confidence,
                updatedAt: now,
              );
              applied++;
            case 'NONE':
            default:
              continue;
          }
        } catch (_) {
          continue; // 坏数据跳过,不影响其余
        }
      }

      if (applied > 0) await _embedPending();
      _turnsSinceExtract = 0;
      notifyListeners();
      return applied;
    } catch (e) {
      // 静默跳过:记忆是增强,不阻塞对话。
      _lastError = '$e';
      return 0;
    }
  }

  /// 给待补向量的记忆补上向量。
  Future<void> _embedPending() async {
    final engine = _engine;
    if (engine == null) return;
    try {
      if (!engine.isLoaded) return;
      while (true) {
        final pending = await _store.pendingForEmbedding(
          modelId: _currentModelId(),
          limit: 8,
        );
        if (pending.isEmpty) break;
        final vecs = await engine.embed(pending.map((p) => p.content).toList());
        for (var i = 0; i < pending.length; i++) {
          await _store.storeEmbedding(
            id: pending[i].id,
            modelId: _currentModelId(),
            vector: vecs[i],
          );
        }
      }
    } catch (e) {
      _lastError = '$e';
    }
  }

  /// 调 LLM 拿操作列表。
  Future<List<MemoryOp>> _askForOps({
    required String speaker,
    required List<ConversationMessage> messages,
    required List<MemoryItem> existing,
  }) async {
    final transcript = StringBuffer();
    for (final m in messages) {
      final who = m.role == ConversationRole.assistant
          ? '助手'
          : (m.speakerName ?? '未知');
      transcript.writeln('[$who] ${m.content}');
    }

    final user = StringBuffer()
      ..writeln('当前说话人: $speaker')
      ..writeln();
    if (existing.isEmpty) {
      user.writeln('【已有记忆】(无)');
    } else {
      user.writeln('【已有记忆】');
      for (final m in existing) {
        user.writeln('- id=${m.id} [${m.kind}] ${m.content}');
      }
    }
    user
      ..writeln()
      ..writeln('【最近对话】')
      ..write(transcript);

    final raw = StringBuffer();
    await for (final delta in _llm.streamChat([
      LlmMessage(role: 'system', content: _extractSystemPrompt),
      LlmMessage(role: 'user', content: user.toString()),
    ])) {
      raw.write(delta);
    }
    return parseMemoryOps(raw.toString());
  }

  String get _extractSystemPrompt =>
      '你是记忆抽取器。从对话中抽取关于**当前说话人**的、跨会话仍然成立的短事实。\n'
      '只输出 JSON 数组,不要任何解释,也不要代码围栏。每项形如:\n'
      '{"op":"ADD","kind":"fact","content":"...","confidence":0.8}\n'
      '或 {"op":"UPDATE","id":3,"kind":"preference","content":"...","confidence":0.9}\n'
      '或 {"op":"NONE"}\n'
      '规则:\n'
      '- 只抽**当前说话人**的信息;别人的话里关于他们自己的内容不要记。\n'
      '- 寒暄、一次性问答、助手说的话,都不要记。\n'
      '- 与已有记忆重复或已被其覆盖 ⇒ 用 UPDATE 并给出对应 id。\n'
      '- 完全是旧信息、没有新增 ⇒ 用 NONE。\n'
      '- content 用第三人称、一句话、不超过 30 字。\n'
      '- 没有可记的就输出 []。';

  /// 解析 LLM 输出为操作列表。
  ///
  /// **必须容错**:LLM 会用 ```json 包起来、会在前后加解释、偶尔给出坏项。
  /// 故:剥围栏 → 取首个 `[` 到末个 `]` → 逐项校验,坏项丢弃而不是整批失败。
  @visibleForTesting
  static List<MemoryOp> parseMemoryOps(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return const [];

    // 剥 ```json ... ``` 围栏
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
    if (fence != null) text = fence.group(1)!.trim();

    // 取数组区间(容忍前后夹带说明文字)
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start < 0 || end <= start) return const [];
    text = text.substring(start, end + 1);

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      return const [];
    }
    if (decoded is! List) return const [];

    final out = <MemoryOp>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final op = (item['op'] as String?)?.trim().toUpperCase();
      if (op == null || op.isEmpty) continue;
      if (op == 'NONE') {
        out.add(const MemoryOp(op: 'NONE', kind: MemoryKind.fact, content: ''));
        continue;
      }
      if (op != 'ADD' && op != 'UPDATE') continue;
      final content = (item['content'] as String?)?.trim() ?? '';
      if (content.isEmpty) continue;
      out.add(MemoryOp(
        op: op,
        kind: MemoryKind.normalize((item['kind'] as String?) ?? MemoryKind.fact),
        content: content,
        id: (item['id'] as num?)?.toInt(),
        confidence: ((item['confidence'] as num?)?.toDouble() ?? 0.7)
            .clamp(0.0, 1.0),
      ));
    }
    return out;
  }
}

