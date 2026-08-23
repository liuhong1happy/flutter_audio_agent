/// WAV 编解码往返 + PCM16 转 float 测试。
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_tts_demo/utils/mic_recorder.dart';
import 'package:flutter_tts_demo/utils/wav_encoder.dart';
import 'package:flutter_tts_demo/utils/wav_reader.dart';

void main() {
  test('wavBytes → decodeWav 单声道往返', () {
    final src = Float32List.fromList([0.0, 0.5, -0.5, 1.0, -1.0, 0.25]);
    final bytes = wavBytes(src, 16000);

    final wav = decodeWav(bytes);
    expect(wav.sampleRate, 16000);
    expect(wav.samples.length, src.length);
    // int16 量化有 ±1/32768 误差,比较到 1e-3。
    for (var i = 0; i < src.length; i++) {
      expect(wav.samples[i], closeTo(src[i], 1e-3));
    }
  });

  test('decodeWav 拒绝非 WAV 输入', () {
    expect(
      () => decodeWav(Uint8List(100)),
      throwsFormatException,
    );
    expect(
      () => decodeWav(Uint8List.fromList('RIFF'.codeUnits)),
      throwsFormatException,
    );
  });

  test('decodeWav 支持立体声下混', () {
    // 手工构造 16-bit 立体声:左声道 32767,右声道 0 → 下混约 0.5。
    final data = Int16List.fromList([32767, 0, -32768, 0]).buffer
        .asUint8List();
    final bytes = _buildWavBytes(data, channels: 2, sampleRate: 16000);
    final wav = decodeWav(bytes);
    expect(wav.samples.length, 2);
    expect(wav.samples[0], closeTo(0.5, 1e-3));
    expect(wav.samples[1], closeTo(-0.5, 1e-3));
  });

  test('pcm16ToFloat32 转换', () {
    final pcm = Int16List.fromList([0, 32767, -32768, 16384]).buffer
        .asUint8List();
    final f = pcm16ToFloat32(pcm);
    expect(f.length, 4);
    expect(f[0], 0.0);
    expect(f[1], closeTo(1.0, 1e-3));
    expect(f[2], closeTo(-1.0, 1e-3));
    expect(f[3], closeTo(0.5, 1e-3));
  });
}

Uint8List _buildWavBytes(
  Uint8List pcmData, {
  required int channels,
  required int sampleRate,
}) {
  final bytesPerSample = 2;
  final blockAlign = channels * bytesPerSample;
  final byteRate = sampleRate * blockAlign;
  final dataSize = pcmData.length;
  final b = BytesBuilder();
  void u16(int v) => b.add([v & 0xff, (v >> 8) & 0xff]);
  void u32(int v) => b.add([
        v & 0xff,
        (v >> 8) & 0xff,
        (v >> 16) & 0xff,
        (v >> 24) & 0xff,
      ]);
  void str(String s) => b.add(s.codeUnits);
  str('RIFF');
  u32(36 + dataSize);
  str('WAVE');
  str('fmt ');
  u32(16);
  u16(1);
  u16(channels);
  u32(sampleRate);
  u32(byteRate);
  u16(blockAlign);
  u16(16);
  str('data');
  u32(dataSize);
  b.add(pcmData);
  return b.toBytes();
}
