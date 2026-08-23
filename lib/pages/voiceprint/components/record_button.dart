/// 圆形居中录音按钮。
library;

import 'package:flutter/material.dart';

import 'package:flutter_tts_demo/components/theme/app_colors.dart';

class RecordButton extends StatelessWidget {
  const RecordButton({super.key, required this.recording, required this.onTap});

  final bool recording;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: recording ? AppColors.danger : AppColors.accent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: recording ? null : onTap,
        child: SizedBox(
          width: 112,
          height: 112,
          child: Icon(
            recording ? Icons.graphic_eq : Icons.mic,
            color: Colors.white,
            size: 48,
          ),
        ),
      ),
    );
  }
}
