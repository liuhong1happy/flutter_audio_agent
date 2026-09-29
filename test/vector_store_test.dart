/// 向量存储 / 暴力点积检索测试。
///
/// 这里的错误大多是**静默**的:检索会返回结果、分数看着也像个分数,只是排序是噪音。
/// 所以断言集中在"数学是否等价于余弦相似度"与"跨模型向量是否被隔离"。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_tts_demo/utils/memory/vector_store.dart';

/// 用 [List] 造单位向量。
Float32List unit(List<double> v) => normalize(Float32List.fromList(v));

/// 独立实现的余弦相似度,用来校验"点积 == 余弦"这一前提。
double cosine(Float32List a, Float32List b) {
  var dot = 0.0, na = 0.0, nb = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  return dot / (math.sqrt(na) * math.sqrt(nb));
}

void main() {
  group('VectorCodec', () {
    test('Float32 往返无损(取 float32 可精确表示的值)', () {
      final v = Float32List.fromList([0.5, -0.25, 0.0, 1.0, -1.0, 0.125]);
      final round = VectorCodec.decode(VectorCodec.encode(v));
      expect(round.length, v.length);
      for (var i = 0; i < v.length; i++) {
        expect(round[i], v[i]);
      }
    });

    test('编码为小端 4 字节/元素,字节数 = 维度 × 4', () {
      final v = Float32List.fromList([1.0, 2.0, 3.0]);
      final bytes = VectorCodec.encode(v);
      expect(bytes.length, 12);
      expect(VectorCodec.dimOf(bytes), 3);
      // 1.0 的小端 float32 = 00 00 80 3F
      expect(bytes.sublist(0, 4), [0x00, 0x00, 0x80, 0x3F]);
    });

    test('512 维 = 2048 字节(存储成本核算)', () {
      final v = Float32List(512);
      expect(VectorCodec.encode(v).length, 2048);
    });

    test('空向量往返', () {
      expect(VectorCodec.decode(VectorCodec.encode(Float32List(0))).length, 0);
      expect(VectorCodec.dimOf(Uint8List(0)), 0);
    });

    test('起始偏移非 4 字节对齐时仍能正确解码(走拷贝回退分支)', () {
      // 造一个 offsetInBytes = 1 的视图,直接 view 会抛,必须回退到拷贝。
      final backing = Uint8List(16);
      final src = Float32List.fromList([1.0, 2.0, 3.0]);
      final encoded = VectorCodec.encode(src);
      for (var i = 0; i < encoded.length; i++) {
        backing[1 + i] = encoded[i];
      }
      final unaligned = Uint8List.sublistView(backing, 1, 1 + encoded.length);
      expect(unaligned.offsetInBytes % 4, isNot(0), reason: '构造失败:偏移是对齐的');

      final decoded = VectorCodec.decode(unaligned);
      expect(decoded, [1.0, 2.0, 3.0]);
    });
  });

  group('normalize', () {
    test('单位向量的模为 1', () {
      final v = unit([3.0, 4.0]);
      expect(math.sqrt(v[0] * v[0] + v[1] * v[1]), closeTo(1.0, 1e-6));
    });

    test('零向量保持为零,不产生 NaN', () {
      final v = normalize(Float32List.fromList([0.0, 0.0, 0.0]));
      expect(v.every((e) => e == 0.0), isTrue);
      expect(v.any((e) => e.isNaN), isFalse);
    });
  });

  group('searchTopK', () {
    test('单位向量的点积 == 余弦相似度(前提校验)', () {
      final a = unit([1.0, 2.0, 3.0]);
      final b = unit([2.0, 1.0, 0.5]);
      final hits = searchTopK(a, [VectorCandidate(id: 1, vector: b)]);
      expect(hits.single.score, closeTo(cosine(a, b), 1e-6));
    });

    test('按相似度降序返回,最相似的排第一', () {
      final q = unit([1.0, 0.0, 0.0]);
      final candidates = [
        VectorCandidate(id: 1, vector: unit([0.0, 1.0, 0.0])), // 正交 → 0
        VectorCandidate(id: 2, vector: unit([1.0, 0.0, 0.0])), // 同向 → 1
        VectorCandidate(id: 3, vector: unit([1.0, 1.0, 0.0])), // 约 0.707
      ];
      final hits = searchTopK(q, candidates);
      expect(hits.map((h) => h.id).toList(), [2, 3, 1]);
      expect(hits[0].score, closeTo(1.0, 1e-6));
      expect(hits[2].score, closeTo(0.0, 1e-6));
    });

    test('反向向量得负分(不是 0,也不是"低正分")', () {
      final q = unit([1.0, 0.0]);
      final hits = searchTopK(q, [
        VectorCandidate(id: 1, vector: unit([-1.0, 0.0])),
      ]);
      expect(hits.single.score, closeTo(-1.0, 1e-6));
    });

    test('阈值过滤:低于 minScore 的不返回', () {
      final q = unit([1.0, 0.0, 0.0]);
      final candidates = [
        VectorCandidate(id: 1, vector: unit([1.0, 0.0, 0.0])), // 1.0
        VectorCandidate(id: 2, vector: unit([0.0, 1.0, 0.0])), // 0.0
      ];
      expect(searchTopK(q, candidates, minScore: 0.5).map((h) => h.id), [1]);
      expect(searchTopK(q, candidates, minScore: -0.1).length, 2);
    });

    test('topK 截断', () {
      final q = unit([1.0, 0.0]);
      final candidates = List.generate(
        10,
        (i) => VectorCandidate(id: i, vector: unit([1.0, i * 0.1])),
      );
      expect(searchTopK(q, candidates, topK: 3).length, 3);
    });

    test('**维度不一致的脏数据被跳过**,不会当成低分候选', () {
      final q = unit([1.0, 0.0, 0.0]);
      final candidates = [
        VectorCandidate(id: 1, vector: unit([1.0, 0.0, 0.0])),
        VectorCandidate(id: 2, vector: unit([1.0, 0.0])), // 2 维,脏数据
      ];
      final hits = searchTopK(q, candidates, minScore: -1.0);
      expect(hits.map((h) => h.id), [1]);
    });

    test('空查询 / 空候选 / topK<=0 → 空结果,不抛错', () {
      final q = unit([1.0, 0.0]);
      expect(searchTopK(Float32List(0), [VectorCandidate(id: 1, vector: q)]),
          isEmpty);
      expect(searchTopK(q, const []), isEmpty);
      expect(searchTopK(q, [VectorCandidate(id: 1, vector: q)], topK: 0),
          isEmpty);
    });

    test('携带文本与负载,便于注入提示词与调试', () {
      final q = unit([1.0, 0.0]);
      final hits = searchTopK(q, [
        VectorCandidate(
          id: 7,
          vector: q,
          text: '产品手册第 3 章',
          payload: {'docId': 2},
        ),
      ]);
      expect(hits.single.text, '产品手册第 3 章');
      expect(hits.single.payload, {'docId': 2});
    });
  });

  group('InMemoryVectorRepository:跨模型隔离(静默错误守卫)', () {
    test('只返回**当前模型**的向量:换模型后旧向量必须不可见', () async {
      // 这是本层最重要的一条。两个嵌入模型维度可能相同(都是 512),混用**不报错**,
      // 只会让相似度变成噪音 —— 与 v1.0.1 两个声纹模型的坑完全同构。
      final repo = InMemoryVectorRepository();
      repo.put(1, unit([1.0, 0.0]), 'model-a', text: 'A 模型的块');
      repo.put(2, unit([0.0, 1.0]), 'model-b', text: 'B 模型的块');

      final a = await repo.loadCandidates(modelId: 'model-a');
      expect(a.map((c) => c.id), [1]);

      final b = await repo.loadCandidates(modelId: 'model-b');
      expect(b.map((c) => c.id), [2]);
    });

    test('未下载/未使用的模型 id 返回空,而不是"回落到全部"', () async {
      final repo = InMemoryVectorRepository();
      repo.put(1, unit([1.0, 0.0]), 'model-a');
      expect(await repo.loadCandidates(modelId: 'model-x'), isEmpty);
    });

    test('storeVector 写入的向量按模型可查', () async {
      final repo = InMemoryVectorRepository();
      await repo.storeVector(id: 5, vector: unit([1.0, 1.0]), modelId: 'm');
      final got = await repo.loadCandidates(modelId: 'm');
      expect(got.single.id, 5);
    });
  });

  group('InMemoryVectorIndex', () {
    test('size / dim / search 正常', () {
      final index = InMemoryVectorIndex([
        VectorCandidate(id: 1, vector: unit([1.0, 0.0, 0.0])),
        VectorCandidate(id: 2, vector: unit([0.0, 1.0, 0.0])),
      ]);
      expect(index.size, 2);
      expect(index.dim, 3);
      expect(index.search(unit([1.0, 0.0, 0.0])).first.id, 1);
    });

    test('空索引的 dim 为 0 且检索为空', () {
      final index = InMemoryVectorIndex(const []);
      expect(index.size, 0);
      expect(index.dim, 0);
      expect(index.search(unit([1.0])), isEmpty);
    });

    test('dispose 释放候选', () {
      final index = InMemoryVectorIndex([
        VectorCandidate(id: 1, vector: unit([1.0])),
      ]);
      index.dispose();
      expect(index.size, 0);
    });
  });
}
