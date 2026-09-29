/// 测试识别弹窗。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tts_demo/components/theme/app_text.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';
import 'package:flutter_tts_demo/utils/voiceprint_service.dart';

import '../utils/record_samples.dart';

class IdentifySheet extends StatefulWidget {
  const IdentifySheet({super.key});

  @override
  State<IdentifySheet> createState() => _IdentifySheetState();
}

class _IdentifySheetState extends State<IdentifySheet> {
  bool _recording = false;
  String? _result;

  Future<void> _identify() async {
    final l10n = AppLocalizations.of(context);
    final service = context.read<VoiceprintService>();
    final samples = await recordSamples(context, (r) {
      if (mounted) setState(() => _recording = r);
    });
    final name = await service.identifyTest(samples, 16000);
    if (mounted) {
      setState(() {
        _result = name.isEmpty ? l10n.speakerUnknown : name;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 显示当前模型:"录了却认不出"多半就是模型对不上,提示放在现场最有效。
    final service = context.watch<VoiceprintService>();
    final currentName = service.displayNameOf(service.currentModelId);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (currentName != null) ...[
            Text(
              l10n.currentVoiceprintModel(currentName),
              key: const ValueKey('identifyModelLabel'),
              style: AppText.caption,
            ),
            const SizedBox(height: 12),
          ],
          FilledButton.tonalIcon(
            onPressed: _recording ? null : _identify,
            icon: Icon(_recording ? Icons.mic : Icons.mic_none),
            label: Text(_recording ? l10n.recording : l10n.identifyTest),
          ),
          if (_result != null) ...[
            const SizedBox(height: 16),
            Text(_result!, style: AppText.headline),
          ],
        ],
      ),
    );
  }
}
