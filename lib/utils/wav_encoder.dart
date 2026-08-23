/// 纯 Dart WAV(16-bit PCM)编码器。
///
/// 不依赖 sherpa_onnx.writeWave,避免在主 isolate 额外加载原生绑定。
library;

import 'dart:typed_data';

/// 把单声道 float32 采样([-1,1])编码为 WAV 字节。
Uint8List wavBytes(Float32List samples, int sampleRate) {
  const bytesPerSample = 2; // int16
  final dataSize = samples.length * bytesPerSample;

  final builder = BytesBuilder();

  void writeString(String s) => builder.add(s.codeUnits);
  void writeU16(int v) =>
      builder.add([v & 0xff, (v >> 8) & 0xff]);
  void writeU32(int v) => builder.add([
        v & 0xff,
        (v >> 8) & 0xff,
        (v >> 16) & 0xff,
        (v >> 24) & 0xff,
      ]);

  writeString('RIFF');
  writeU32(36 + dataSize);
  writeString('WAVE');
  writeString('fmt ');
  writeU32(16); // fmt 块大小
  writeU16(1); // PCM
  writeU16(1); // 单声道
  writeU32(sampleRate);
  writeU32(sampleRate * bytesPerSample); // byte rate
  writeU16(bytesPerSample); // block align
  writeU16(16); // 位深
  writeString('data');
  writeU32(dataSize);

  final pcm = Int16List(samples.length);
  for (var i = 0; i < samples.length; i++) {
    final s = samples[i].clamp(-1.0, 1.0);
    pcm[i] = (s * 32767).round();
  }
  builder.add(pcm.buffer.asUint8List());
  return builder.toBytes();
}
