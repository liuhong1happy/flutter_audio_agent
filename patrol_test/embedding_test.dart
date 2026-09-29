/// 设备侧验证:本地文本向量化(`flutter_embedder` + bge-small-zh-v1.5)。
///
/// 这是 v1.0.2 最重的一块新依赖,**必须在真机/模拟器上跑**,原因有三:
///  1. 它走 Rust FFI,**桌面/node 侧的对照说明不了设备行为**;
///  2. 嵌入是**同步 FFI**,必须确认它跑在后台 isolate 里、不阻塞 UI;
///  3. 整个方案成立的前提是:`ort` 的 `load-dynamic` **能加载 sherpa 已打进 APK 的
///     那份 `libonnxruntime.so`** —— 这一条只有设备上能证。
///
/// 运行(需已连接 Android 设备/模拟器):
///   patrol test -t patrol_test/embedding_test.dart
///
/// 首次运行会从 **ModelScope** 真实下载 2 个文件(约 24.5MB,实测直连约 2.6s)。
///
/// ⚠️ **为什么放在 patrol_test 而不是 integration_test**:加 `integration_test`
/// 这个 dev 依赖会让 Flutter 重新生成的 `GeneratedPluginRegistrant.java` 把
/// dev-only 插件也写进去,而 release 变体的 classpath 没有这些类 ⇒
/// **`flutter build apk --release` 直接编译失败**。实测过:去掉它 release 就过。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_embedder/flutter_embedder.dart';
import 'package:patrol/patrol.dart';

import 'package:flutter_tts_demo/utils/memory/embedding_engine.dart';

/// 模型的 ModelScope 源(**单文件** ONNX,已实测 200 / 206 / ONNX 魔数)。
///
/// ⚠️ 用 `Xenova/bge-small-zh-v1.5`。**勿换**成
/// `onnx-community/bge-small-zh-v1.5-ONNX` —— 那份是 `.onnx`(168KB 图)
/// + `.onnx_data`(23.8MB 权重)的**外置数据**拆分格式,只下 `.onnx` 必然加载失败。
const String _modelBase =
    'https://modelscope.cn/models/Xenova/bge-small-zh-v1.5/resolve/master';

const Map<String, String> _modelFiles = {
  'onnx/model_quantized.onnx': 'model_quantized.onnx',
  'tokenizer.json': 'tokenizer.json',
};

const Map<String, int> _expectedSizes = {
  'model_quantized.onnx': 24010842,
  'tokenizer.json': 439125,
};

/// 落盘目录。
///
/// ⚠️ **刻意不用 `path_provider`**:它在 Android 上走 `package:jni`,
/// 而 patrol/integration 这类测试环境下 Dart 侧插件初始化时序不一定就绪,
/// 会抛 `No JNI instance is available`。
/// 路径已从 path_provider_android 源码确认:
/// `getApplicationDocumentsPath()` = `context.getDir("flutter", MODE_PRIVATE)`
/// ⇒ `/data/user/0/<pkg>/app_flutter`(**不是** `files` —— 那是 support 目录)。
const String _androidPackage = 'top.ued17.tts';

Future<Directory> _ensureModelFiles() async {
  final dir = Directory(
    '/data/user/0/$_androidPackage/app_flutter/embedding_spike',
  );
  await dir.create(recursive: true);
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(minutes: 5),
  ));
  for (final entry in _modelFiles.entries) {
    final target = File('${dir.path}/${entry.value}');
    final expected = _expectedSizes[entry.value]!;
    if (await target.exists() && await target.length() == expected) continue;
    final resp = await dio.get<List<int>>(
      '$_modelBase/${entry.key}',
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = resp.data!;
    if (bytes.length != expected) {
      throw StateError('${entry.value} 体积不符(可能拿到 HTML 拦截页)');
    }
    await target.writeAsBytes(bytes, flush: true);
  }
  return dir;
}

double _cos(Float32List a, Float32List b) {
  var d = 0.0;
  for (var i = 0; i < a.length; i++) {
    d += a[i] * b[i];
  }
  return d;
}

void main() {
  // ⚠️ 用例名里**不能出现 `/`**:Android Test Orchestrator 会拿用例名当文件名
  // (`<用例名>.txt`),遇到路径分隔符直接抛 IllegalArgumentException 并把自己
  // 杀掉,表现为整轮 "Total: 0 / Process crashed" —— 看起来像 App 崩了,其实
  // 一个用例都没跑。见 TODO.md 坑 46。
  patrolTest('嵌入引擎:加载 + 语义 + 后台 isolate 不阻塞 UI', ($) async {
    // 不需要界面,但 patrol 的 finder 需要一个根。
    await $.pumpWidgetAndSettle(const MaterialApp(home: SizedBox()));

    final dir = await _ensureModelFiles();

    // ── 1. 插件层:验证"ort 能加载 sherpa 那份 libonnxruntime.so" ──
    // initFlutterEmbedder 内部就是 ffi.DynamicLibrary.open('libonnxruntime.so'),
    // 而 APK 里这份由 **sherpa_onnx** 提供(我们刻意不引入 onnxruntime-android)。
    final sw = Stopwatch()..start();
    await initFlutterEmbedder(path: kOrtLibraryName);
    sw.stop();
    debugPrint('[spike] initFlutterEmbedder 成功,${sw.elapsedMilliseconds}ms');

    final bge = BgeEmbedder.create(
      modelPath: '${dir.path}/model_quantized.onnx',
      tokenizerPath: '${dir.path}/tokenizer.json',
    );
    try {
      final first = bge.embed(texts: ['今天天气很好']);
      if (first.first.length != kEmbeddingDim) {
        throw StateError('维度应为 $kEmbeddingDim,实际 ${first.first.length}');
      }

      // ── 2. 语义判别力(池化/归一化正确的证据)──
      final vecs = bge.embed(texts: [
        '我明天要去北京出差',
        '明天我要去北京办事',
        '这个函数返回一个整型列表',
      ]);
      final same = _cos(vecs[0], vecs[1]);
      final diff = _cos(vecs[0], vecs[2]);
      debugPrint('[spike] 同义=$same 异义=$diff');
      if (same <= diff) {
        throw StateError('同义句相似度未高于异义句,检索不可用');
      }

      // ── 3. 边界:超过 512 token 必须**响亮失败**(而不是静默截断丢内容)──
      final tooLong = '这是一段用来触发超长报错的中文文本。' * 60;
      var threw = false;
      try {
        bge.embed(texts: [tooLong]);
      } catch (_) {
        threw = true;
      }
      if (!threw) {
        throw StateError('超长输入没有被拒绝,插件可能在静默截断');
      }
    } finally {
      bge.dispose();
    }

    // ── 4. 引擎层:后台 isolate 内建会话,且**嵌入期间 UI isolate 不被阻塞** ──
    final engine = FlutterEmbedderEngine();
    try {
      await engine.load(
        modelPath: '${dir.path}/model_quantized.onnx',
        tokenizerPath: '${dir.path}/tokenizer.json',
      );
      final block = '语音对话系统由离线识别、离线合成与声纹识别三部分组成,' * 5;
      final texts = List.generate(16, (i) => '$block 第$i段。');

      var ticks = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 20),
        (_) => ticks++,
      );
      final t = Stopwatch()..start();
      final out = await engine.embed(texts);
      t.stop();
      timer.cancel();
      debugPrint('[spike] 16 条经隔离区 ${t.elapsedMilliseconds}ms,'
          '期间 UI isolate 推进 $ticks 次(20ms 周期)');

      if (out.length != 16) throw StateError('返回条数不符');
      // 若 FFI 跑在 UI isolate 上,ticks 会接近 0。
      if (t.elapsedMilliseconds > 200 && ticks <= 3) {
        throw StateError('嵌入期间 UI isolate 明显停摆 —— FFI 没跑在后台 isolate');
      }
    } finally {
      await engine.unload();
    }

    debugPrint('[spike] 全部通过');
  });
}
