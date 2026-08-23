/// 纯 Dart WAV(16-bit PCM)解码器。
///
/// 与 [wavBytes] 编码器相对,在主 isolate 解出参考音频的浮点采样,
/// 避免碰 sherpa_onnx.writeWave/readWave(那会加载原生绑定)。
library;

import 'dart:typed_data';

/// 解码后的 WAV 数据。
class WavData {
  const WavData({required this.samples, required this.sampleRate});

  /// 单声道 float32 采样([-1,1])。
  final Float32List samples;
  final int sampleRate;
}

/// 纯 Dart WAV 读取器。
class WavReader {
  const WavReader();

  /// 解析 [bytes] 为 [WavData]。
  WavData read(Uint8List bytes) => decodeWav(bytes);
}

/// 解析 RIFF/WAVE 字节(16-bit 有符号 PCM,`fmt ` PCM=1 或
/// EXTENSIBLE 0xFFFE;多声道下混为单声道)。
WavData decodeWav(Uint8List bytes) {
  if (bytes.length < 44) {
    throw const FormatException('无效 WAV:文件过短');
  }
  final view = ByteData.sublistView(bytes);

  if (String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF') {
    throw const FormatException('无效 WAV:缺少 RIFF 头');
  }
  if (String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
    throw const FormatException('无效 WAV:缺少 WAVE 标记');
  }

  var sampleRate = 0;
  var channels = 1;
  var bitsPerSample = 16;
  var audioFormat = 1;
  Uint8List? data;

  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = view.getUint32(offset + 4, Endian.little);
    final bodyStart = offset + 8;
    final bodyEnd = bodyStart + size;
    if (bodyEnd > bytes.length) break;

    if (id == 'fmt ') {
      audioFormat = view.getUint16(bodyStart, Endian.little);
      channels = view.getUint16(bodyStart + 2, Endian.little);
      sampleRate = view.getUint32(bodyStart + 4, Endian.little);
      bitsPerSample = view.getUint16(bodyStart + 14, Endian.little);
    } else if (id == 'data') {
      data = Uint8List.sublistView(bytes, bodyStart, bodyEnd);
    }
    // 块体按 2 字节对齐,奇数大小补 1 字节 padding。
    offset = bodyEnd + (size & 1);
  }

  if (data == null) {
    throw const FormatException('无效 WAV:缺少 data 块');
  }
  if (audioFormat != 1 && audioFormat != 0xFFFE) {
    throw FormatException('不支持的 WAV 编码格式: $audioFormat');
  }
  if (bitsPerSample != 16) {
    throw FormatException('仅支持 16-bit PCM,实际 $bitsPerSample bit');
  }

  final frames = data.length ~/ 2 ~/ channels;
  final samples = Float32List(frames);
  final pcm = ByteData.sublistView(data);
  var i = 0;
  for (var f = 0; f < frames; f++) {
    var sum = 0.0;
    for (var c = 0; c < channels; c++) {
      sum += pcm.getInt16(i, Endian.little);
      i += 2;
    }
    samples[f] = (sum / channels / 32768.0).clamp(-1.0, 1.0);
  }
  return WavData(samples: samples, sampleRate: sampleRate);
}
