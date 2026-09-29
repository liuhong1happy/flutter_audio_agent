/// 向量存储与相似度检索。
///
/// 设计取舍(见设计文档第五节):
///  - **存 SQLite BLOB**,不引向量数据库。512 维 × 4B = 2048 B/块。
///  - **检索用内存暴力点积**,不建 ANN 索引。单位向量 ⇒ 余弦相似度 = 点积,
///    省掉除法与开方。1 万块 = 512 万次乘加 = 数毫秒,延迟不可感知;
///    HNSW/IVF 在这个规模只带来构建成本、内存开销与"近似召回漏掉正确块"的新失败模式。
///    **规模上限:约 5 万块之后再考虑 ANN 或按文档分页。**
///  - **不做 FTS5**:Android 系统 SQLite 在 minSdk 23 上不保证 FTS5 可用,且这里是向量检索。
///  - **`model_id` 必须参与过滤**:换嵌入模型后新旧向量不可比,而两者维度相同 ⇒
///    混用**不报错**,只会让排序变成噪音(与 v1.0.1 两个声纹模型同类的静默错误)。
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// 一条命中的检索结果。
class VectorHit {
  const VectorHit({
    required this.id,
    required this.score,
    this.text,
    this.payload,
  });

  /// 来源行 id。
  final int id;

  /// 余弦相似度(单位向量点积,范围约 [-1, 1])。
  final double score;

  /// 命中的原文(便于直接注入提示词与做"检索试跑"调试)。
  final String? text;

  /// 附加负载(如 KB 块的 doc_id / 长期记忆的 speaker)。
  final Object? payload;

  @override
  String toString() =>
      'VectorHit(id=$id, score=${score.toStringAsFixed(4)}'
      '${text == null ? '' : ', text=${text!.length}字'})';
}

/// Float32 向量 ↔ BLOB 编解码。
class VectorCodec {
  VectorCodec._();

  static Uint8List encode(Float32List v) {
    final bytes = Uint8List(v.length * 4);
    final view = ByteData.view(bytes.buffer);
    for (var i = 0; i < v.length; i++) {
      view.setFloat32(i * 4, v[i], Endian.little);
    }
    return bytes;
  }

  /// 零拷贝解码:直接以 [Float32List] 视图读同一段内存。
  ///
  /// 依赖 sqflite 返回的 Uint8List 起始偏移是 4 字节对齐的;不对齐时退回拷贝,
  /// 避免抛错(`Float32List.view` 对非对齐偏移会抛)。
  static Float32List decode(Uint8List bytes) {
    if (bytes.isEmpty) return Float32List(0);
    const align = 4;
    final offsetOk = bytes.offsetInBytes % align == 0;
    if (offsetOk) {
      return Float32List.view(
        bytes.buffer,
        bytes.offsetInBytes,
        bytes.lengthInBytes ~/ 4,
      );
    }
    final copy = Uint8List.fromList(bytes);
    return Float32List.view(copy.buffer, 0, copy.lengthInBytes ~/ 4);
  }

  /// 向量维度(按字节数推算)。用于识别"维度对不上"的脏数据。
  static int dimOf(Uint8List bytes) => bytes.lengthInBytes ~/ 4;
}

/// 一条候选(已解码的向量 + 元数据)。
class VectorCandidate {
  const VectorCandidate({
    required this.id,
    required this.vector,
    this.text,
    this.payload,
  });

  final int id;
  final Float32List vector;
  final String? text;
  final Object? payload;
}

/// 不设阈值的哨兵值。
///
/// **过滤是调用方的显式决定,不藏在默认值里** —— 若默认就滤掉 0 分以下的候选,
/// 调用方会拿到"比给进去的候选少"的结果却看不出原因。业务阈值(如
/// `kbScoreThreshold = 0.45`)属于设置层,由调用方显式传入。
const double kNoScoreThreshold = double.negativeInfinity;

/// 暴力点积 top-k 检索(**纯函数,无 IO,便于单测**)。
///
/// [query] 必须是 L2 归一化后的单位向量;候选也必须是单位向量(存储时已归一化)。
/// 这样才能用点积等价余弦相似度。
List<VectorHit> searchTopK(
  Float32List query,
  List<VectorCandidate> candidates, {
  int topK = 4,
  double minScore = kNoScoreThreshold,
}) {
  if (topK <= 0 || candidates.isEmpty || query.isEmpty) return const [];

  final hits = <VectorHit>[];
  for (final c in candidates) {
    // 维度不一致的脏数据直接跳过 —— 不要让它参与计算后被误当成"低分"。
    if (c.vector.length != query.length) continue;

    var dot = 0.0;
    for (var i = 0; i < query.length; i++) {
      dot += query[i] * c.vector[i];
    }
    if (dot < minScore) continue;
    hits.add(VectorHit(
      id: c.id,
      score: dot,
      text: c.text,
      payload: c.payload,
    ));
  }

  // 规模上限约 5 万块,整体排序 (O(N log N)) 远快于引入部分选择结构带来的复杂度。
  hits.sort((a, b) => b.score.compareTo(a.score));
  return hits.length > topK ? hits.sublist(0, topK) : hits;
}

/// 内存中的候选集,从 SQLite 载入后复用。
///
/// 一次查询只读一次库:把候选载入内存后反复检索(「检索试跑」等调试场景会连续查很多次)。
class InMemoryVectorIndex {
  InMemoryVectorIndex(this._candidates);

  final List<VectorCandidate> _candidates;

  int get size => _candidates.length;

  /// 载入时的维度;空集为 0。
  int get dim => _candidates.isEmpty ? 0 : _candidates.first.vector.length;

  List<VectorHit> search(
    Float32List query, {
    int topK = 4,
    double minScore = kNoScoreThreshold,
  }) =>
      searchTopK(query, _candidates, topK: topK, minScore: minScore);

  /// 释放内存(载入的向量可能占几十 MB)。
  void dispose() => _candidates.clear();
}

/// 向量表的读写抽象。
///
/// 具体表结构由调用方(KnowledgeService / MemoryService)定义,这里只约定
/// "按过滤条件载入候选"与"写入向量"两件事。
abstract class VectorRepository {
  /// 载入符合条件的候选向量。
  ///
  /// [modelId] 是**必填**过滤条件:不同嵌入模型的向量不可比,而维度相同不会报错。
  Future<List<VectorCandidate>> loadCandidates({
    required String modelId,
    Object? filter,
  });

  /// 写入一条向量。
  Future<void> storeVector({
    required int id,
    required Float32List vector,
    required String modelId,
  });
}

/// 供测试与轻量场景使用的内存实现。
class InMemoryVectorRepository implements VectorRepository {
  final Map<int, _Stored> _rows = {};

  @override
  Future<List<VectorCandidate>> loadCandidates({
    required String modelId,
    Object? filter,
  }) async {
    final out = <VectorCandidate>[];
    _rows.forEach((id, s) {
      if (s.modelId != modelId) return; // ⚠️ 跨模型向量绝不可比。
      if (filter != null && s.payload != filter) return;
      out.add(VectorCandidate(
        id: id,
        vector: s.vector,
        text: s.text,
        payload: s.payload,
      ));
    });
    return out;
  }

  @override
  Future<void> storeVector({
    required int id,
    required Float32List vector,
    required String modelId,
  }) async {
    _rows[id] = _Stored(vector, modelId, null, null);
  }

  /// 测试辅助:带文本/负载写入。
  void put(int id, Float32List vector, String modelId,
      {String? text, Object? payload}) {
    _rows[id] = _Stored(vector, modelId, text, payload);
  }
}

class _Stored {
  _Stored(this.vector, this.modelId, this.text, this.payload);
  final Float32List vector;
  final String modelId;
  final String? text;
  final Object? payload;
}

/// 生成一个 L2 归一化的向量(工具方法,测试与建索引用)。
Float32List normalize(Float32List v) {
  var sum = 0.0;
  for (var i = 0; i < v.length; i++) {
    sum += v[i] * v[i];
  }
  final norm = math.sqrt(sum);
  final out = Float32List(v.length);
  if (norm <= 1e-12) return out;
  for (var i = 0; i < v.length; i++) {
    out[i] = v[i] / norm;
  }
  return out;
}
