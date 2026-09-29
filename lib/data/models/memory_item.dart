/// 长期记忆条目(跨会话成立、**挂在说话人身上**的事实)。
///
/// 与知识库的本质差别:知识库是**用户主动导入的资料**,长期记忆是
/// **从对话里推断出来的事实**。两者混在一张表会导致"我明明没导入过这个"的困惑,
/// 也会让"删除某人记忆"顺手删掉知识库(或反之),所以**分开存、分开删**。
library;

import 'dart:typed_data';

/// 记忆类型。
///
/// 用字符串而非枚举存库:LLM 抽取时给的就是字符串,加新类型不必迁移表结构;
/// 未知类型一律按 [MemoryKind.fact] 显示,不丢数据。
class MemoryKind {
  const MemoryKind._();

  /// 事实(如"在做 Flutter 语音项目")。
  static const String fact = 'fact';

  /// 偏好(如"偏好简洁回答")。
  static const String preference = 'preference';

  /// 事件(如"月末要去北京出差")。
  static const String event = 'event';

  /// 关系(如"和张三是同事")。
  static const String relation = 'relation';

  static const Set<String> all = {fact, preference, event, relation};

  /// 归一化:未知类型回落到 [fact],而不是丢弃。
  static String normalize(String raw) {
    final v = raw.trim().toLowerCase();
    return all.contains(v) ? v : fact;
  }
}

/// 一条长期记忆。
class MemoryItem {
  const MemoryItem({
    required this.id,
    required this.speaker,
    required this.kind,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.embedding,
    this.dim,
    this.modelId,
    this.confidence = 0.7,
    this.sourceMsgId,
  });

  final int id;

  /// 归属说话人(声纹识别出的名字)。
  ///
  /// **必须有**:没有归属的记忆无法做隔离,而把 A 的记忆注入给 B 是
  /// 极难察觉的跨人泄漏(听起来还很自然)。
  final String speaker;

  final String kind;
  final String content;

  final Float32List? embedding;
  final int? dim;
  final String? modelId;

  /// 置信度(0~1)。低于阈值的记忆**不注入**提示词。
  final double confidence;

  /// 来源消息 id(可追溯这条记忆是从哪句话得出的)。
  final int? sourceMsgId;

  final int createdAt;
  final int updatedAt;

  bool get isEmbedded => embedding != null && modelId != null;

  @override
  String toString() =>
      'MemoryItem($id, $speaker/$kind, ${content.length}字, conf=$confidence)';
}
