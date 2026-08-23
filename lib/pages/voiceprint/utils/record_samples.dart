/// 声纹页专属辅助方法:录一段 16kHz 语音。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tts_demo/data/app_dependencies.dart';
import 'package:flutter_tts_demo/utils/mic_recorder.dart';

/// 录一段 16kHz 语音,返回 float 采样。
Future<Float32List> recordSamples(
  BuildContext context,
  void Function(bool recording) onState,
) async {
  final mic = context.read<AppDependencies>().micRecorder;
  await mic.hasPermission();
  final stream = await mic.startStream(sampleRate: 16000);
  final builder = BytesBuilder();
  final sub = stream.listen(builder.add);
  onState(true);
  await Future<void>.delayed(const Duration(seconds: 3));
  await sub.cancel();
  await mic.stopStream();
  onState(false);
  return pcm16ToFloat32(builder.toBytes());
}
