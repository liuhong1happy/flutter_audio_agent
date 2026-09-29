/// 知识库的文档与切块实体。
library;

import 'dart:typed_data';

/// 一篇已导入的知识库文档。
class KbDocument {
  const KbDocument({
    required this.id,
    required this.title,
    required this.importedAt,
    required this.charCount,
    required this.chunkCount,
    required this.embeddedCount,
    this.sourcePath,
  });

  final int id;
  final String title;

  /// 来源文件路径(粘贴文本时为 null)。
  final String? sourcePath;

  final int importedAt;
  final int charCount;
  final int chunkCount;

  /// 已回填向量的块数。
  final int embeddedCount;

  /// 索引进度 0..1(块数为 0 时视为已完成,避免除零)。
  double get indexProgress =>
      chunkCount == 0 ? 1.0 : (embeddedCount / chunkCount).clamp(0.0, 1.0);

  /// 是否已全部回填。
  bool get isIndexed => chunkCount == 0 || embeddedCount >= chunkCount;

  /// 是否正在索引中(有块但没回填完)。
  bool get isIndexing => !isIndexed;

  @override
  String toString() =>
      'KbDocument(id=$id, $title, $embeddedCount/$chunkCount)';
}

/// 知识库中的一块切块。
class KbChunkRecord {
  const KbChunkRecord({
    required this.id,
    required this.docId,
    required this.seq,
    required this.text,
    this.embedding,
    this.dim,
    this.modelId,
  });

  final int id;
  final int docId;
  final int seq;
  final String text;

  /// 语义向量(L2 归一化后的单位向量);未回填时为 null。
  final Float32List? embedding;

  final int? dim;

  /// 生成该向量所用的嵌入模型 id。
  ///
  /// ⚠️ **不可省**:换模型后新旧向量不可比,而两者维度相同 ⇒ 混用**不报错**,
  /// 只让排序变成噪音(与 v1.0.1 两个声纹模型同类的静默错误)。
  /// 检索只取 `model_id == 当前模型` 的块;不匹配的按"未嵌入"处理并重建。
  final String? modelId;

  bool get isEmbedded => embedding != null && modelId != null;

  @override
  String toString() => 'KbChunkRecord($id, doc=$docId, seq=$seq, '
      '${text.length}字, ${isEmbedded ? '已嵌入' : '待嵌入'})';
}
