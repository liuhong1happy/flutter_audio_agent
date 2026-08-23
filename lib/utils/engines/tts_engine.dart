/// TTS 引擎抽象与 sherpa-onnx 后台 isolate 实现。
///
/// sherpa_onnx 要求每个 isolate 先 `initBindings()`;合成会阻塞调用线程,
/// 因此真正的合成放在后台 isolate 中,主 isolate 通过 [IsolateBridge]
/// 请求/接收音频块,保证 UI 不卡顿。
library;

import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'package:flutter_tts_demo/data/model_files_resolver.dart';
import 'package:flutter_tts_demo/data/models/tts_model.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/utils/isolate_bridge.dart';

/// 一次合成产出的音频。
@immutable
class GeneratedAudioData {
  const GeneratedAudioData({required this.samples, required this.sampleRate});

  final Float32List samples;
  final int sampleRate;
}

/// 引擎接口(便于 patrol 测试注入假实现)。
abstract class TtsEngine {
  bool get isLoaded;

  /// 加载模型(后台执行,不阻塞 UI)。
  Future<void> load({
    required ResolvedModelPaths paths,
    required TtsModel model,
    required TtsSettings settings,
  });

  /// 同步合成一句文本。
  Future<GeneratedAudioData> generate({
    required String text,
    required int sid,
    required double speed,
  });

  void dispose();
}

/// 基于 sherpa-onnx 的引擎,在独立 isolate 中运行。
class SherpaTtsEngine implements TtsEngine {
  SherpaTtsEngine() : _bridge = IsolateBridge(_workerEntry, debugName: 'sherpa-tts-worker');

  final IsolateBridge _bridge;
  bool _isLoaded = false;

  @override
  bool get isLoaded => _isLoaded;

  @override
  Future<void> load({
    required ResolvedModelPaths paths,
    required TtsModel model,
    required TtsSettings settings,
  }) async {
    final result = await _bridge.request('load', _LoadPayload(
      family: model.family.name,
      model: paths.modelPath ?? '',
      tokens: paths.tokensPath ?? '',
      lexicon: paths.lexiconPath ?? '',
      voices: paths.voicesPath ?? '',
      dataDir: paths.dataDir ?? '',
      ruleFsts: paths.ruleFsts.join(','),
      numThreads: settings.numThreads,
    ));
    if (result is! int || result <= 0) {
      throw StateError('模型加载失败: $result');
    }
    _isLoaded = true;
  }

  @override
  Future<GeneratedAudioData> generate({
    required String text,
    required int sid,
    required double speed,
  }) async {
    if (!_isLoaded) {
      throw StateError('引擎未加载模型');
    }
    final result = await _bridge.request('generate', _GeneratePayload(
      text: text,
      sid: sid,
      speed: speed,
    ));
    if (result is! List || result.length < 2) {
      throw StateError('合成返回异常');
    }
    final payload0 = result[0];
    final sampleRate = result[1] as int;
    final Float32List samples;
    if (payload0 is TransferableTypedData) {
      // 正常路径:零拷贝移交采样缓冲区。
      samples = payload0.materialize().asFloat32List();
    } else if (payload0 is Float32List) {
      // 空音频兜底路径。
      samples = payload0;
    } else {
      throw StateError('合成返回异常');
    }
    if (samples.isEmpty) {
      throw StateError('合成结果为空');
    }
    return GeneratedAudioData(samples: samples, sampleRate: sampleRate);
  }

  @override
  void dispose() {
    _isLoaded = false;
    _bridge.dispose();
  }
}

// ── 后台 isolate 消息 ────────────────────────────────────────────────

class _LoadPayload {
  const _LoadPayload({
    required this.family,
    required this.model,
    required this.tokens,
    required this.lexicon,
    required this.voices,
    required this.dataDir,
    required this.ruleFsts,
    required this.numThreads,
  });
  final String family;
  final String model;
  final String tokens;
  final String lexicon;
  final String voices;
  final String dataDir;
  final String ruleFsts;
  final int numThreads;
}

class _GeneratePayload {
  const _GeneratePayload({
    required this.text,
    required this.sid,
    required this.speed,
  });
  final String text;
  final int sid;
  final double speed;
}

/// worker isolate 入口:先 initBindings,再响应 load/generate 命令。
void _workerEntry(SendPort mainPort) {
  sherpa_onnx.initBindings();
  sherpa_onnx.OfflineTts? tts;
  final control = ReceivePort();
  mainPort.send(control.sendPort);

  control.listen((msg) {
    if (msg is BridgeRequest) {
      try {
        switch (msg.kind) {
          case 'load':
            final p = msg.payload as _LoadPayload;
            final model = p.family == 'kokoro'
                ? sherpa_onnx.OfflineTtsModelConfig(
                    kokoro: sherpa_onnx.OfflineTtsKokoroModelConfig(
                      model: p.model,
                      voices: p.voices,
                      tokens: p.tokens,
                      dataDir: p.dataDir,
                      lexicon: p.lexicon,
                    ),
                    numThreads: p.numThreads,
                    debug: false,
                    provider: 'cpu',
                  )
                : sherpa_onnx.OfflineTtsModelConfig(
                    vits: sherpa_onnx.OfflineTtsVitsModelConfig(
                      model: p.model,
                      lexicon: p.lexicon,
                      tokens: p.tokens,
                    ),
                    numThreads: p.numThreads,
                    debug: false,
                    provider: 'cpu',
                  );
            tts?.free();
            final loaded = sherpa_onnx.OfflineTts(sherpa_onnx.OfflineTtsConfig(
              model: model,
              ruleFsts: p.ruleFsts,
              maxNumSenetences: 1,
            ));
            tts = loaded;
            mainPort.send(BridgeReply(
              id: msg.id,
              payload: loaded.sampleRate,
            ));
          case 'generate':
            final g = msg.payload as _GeneratePayload;
            final current = tts;
            if (current == null) {
              mainPort.send(BridgeReply(id: msg.id, error: '模型未加载'));
              break;
            }
            final audio = current.generate(
              text: g.text,
              sid: g.sid,
              speed: g.speed,
            );
            // 用 TransferableTypedData 零拷贝移交采样数据,避免长文本下
            // 逐段 Float32List 跨 isolate 拷贝的开销。
            final Object samplesPayload = audio.samples.isNotEmpty
                ? TransferableTypedData.fromList([audio.samples])
                : Float32List(0);
            mainPort.send(BridgeReply(
              id: msg.id,
              payload: [samplesPayload, audio.sampleRate],
            ));
          default:
            mainPort.send(BridgeReply(id: msg.id, error: '未知命令'));
        }
      } catch (e, stack) {
        debugPrint('TTS worker error: $e\n$stack');
        mainPort.send(BridgeReply(id: msg.id, error: '$e'));
      }
    }
  });
}
