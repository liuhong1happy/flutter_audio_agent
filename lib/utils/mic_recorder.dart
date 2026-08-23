/// 麦克风录音抽象 + `record` 包实现。
///
/// 两种用途:
/// - **对话流**:`startStream` 持续输出 16kHz 单声道 PCM16 字节流,
///   消费方转成 Float32List 喂给 VAD/ASR/声纹引擎。
/// - **克隆参考**:`start(path, wav, 24kHz)` 落盘 WAV,`stop` 后用
///   [WavReader] 解出参考采样。
library;

import 'dart:typed_data';

import 'package:record/record.dart';

/// 16-bit 小端 PCM 字节 → 单声道 float32([-1,1]) 采样。
Float32List pcm16ToFloat32(Uint8List bytes) {
  final n = bytes.length ~/ 2;
  final out = Float32List(n);
  final view = ByteData.sublistView(bytes);
  for (var i = 0; i < n; i++) {
    out[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}

/// 麦克风接口(便于测试注入假实现)。
abstract class MicRecorder {
  /// 检查/请求录音权限。
  Future<bool> hasPermission({bool request = true});

  /// 开始持续 PCM16 流录音,返回原始字节流。
  Future<Stream<Uint8List>> startStream({int sampleRate = 16000});

  /// 停止流录音。
  Future<void> stopStream();

  /// 开始录制到 WAV 文件(克隆参考)。
  Future<void> start({required String path, required int sampleRate});

  /// 停止文件录音。
  Future<void> stop();

  Future<void> dispose();
}

/// 基于 `record` 包的实现。
class RecordMicRecorder implements MicRecorder {
  RecordMicRecorder({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  bool _streaming = false;
  bool _fileRecording = false;

  @override
  Future<bool> hasPermission({bool request = true}) =>
      _recorder.hasPermission(request: request);

  @override
  Future<Stream<Uint8List>> startStream({int sampleRate = 16000}) async {
    if (_streaming) await stopStream();
    _streaming = true;
    return _recorder.startStream(RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRate,
      numChannels: 1,
    ));
  }

  @override
  Future<void> stopStream() async {
    if (!_streaming) return;
    _streaming = false;
    await _recorder.stop();
  }

  @override
  Future<void> start({required String path, required int sampleRate}) async {
    if (_fileRecording) await stop();
    _fileRecording = true;
    await _recorder.start(
      RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: sampleRate,
        numChannels: 1,
      ),
      path: path,
    );
  }

  @override
  Future<void> stop() async {
    if (!_fileRecording) return;
    _fileRecording = false;
    await _recorder.stop();
  }

  @override
  Future<void> dispose() async {
    await _recorder.dispose();
  }
}
