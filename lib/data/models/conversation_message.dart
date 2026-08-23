/// 对话消息模型(与存储解耦,供 store / service / UI 共用)。
library;

import 'package:flutter/foundation.dart';

/// 对话消息角色。
enum ConversationRole { user, assistant }

/// 一条对话消息(单一时间线,含说话人徽章与时间戳)。
@immutable
class ConversationMessage {
  const ConversationMessage({
    this.id,
    required this.role,
    required this.content,
    this.speakerName,
    required this.createdAt,
  });

  /// 数据库自增 id(未持久化时为 null)。
  final int? id;

  final ConversationRole role;
  final String content;

  /// 用户消息的说话人名字(null = 未知/访客)。
  final String? speakerName;

  /// 毫秒时间戳。
  final int createdAt;
}
