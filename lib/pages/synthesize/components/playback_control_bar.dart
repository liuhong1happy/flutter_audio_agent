/// 紧凑播放控制条:播放/暂停、进度、停止。
library;

import 'package:flutter/material.dart';

import 'package:flutter_tts_demo/components/theme/app_colors.dart';
import 'package:flutter_tts_demo/components/theme/app_spacing.dart';
import 'package:flutter_tts_demo/components/theme/app_text.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';
import 'package:flutter_tts_demo/utils/tts_streaming_service.dart';

import '../utils/phase_helpers.dart';

class PlaybackControlBar extends StatelessWidget {
  const PlaybackControlBar({
    super.key,
    required this.service,
    required this.onTogglePlayPause,
    required this.onStop,
  });

  final TtsStreamingService service;
  final Future<void> Function() onTogglePlayPause;
  final VoidCallback onStop;

  bool get _isActive => isActiveStreamingPhase(service.phase);
  bool get _isPaused => service.phase == StreamingPhase.paused;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final current = service.currentSegment + 1;
    final total = service.segments.length;
    final phaseText = switch (service.phase) {
      StreamingPhase.idle => l10n.phaseIdle,
      StreamingPhase.preparing => l10n.phasePreparing,
      StreamingPhase.synthesizing => l10n.phaseSynthesizing,
      StreamingPhase.playing => l10n.phasePlaying(current, total),
      StreamingPhase.paused => l10n.phasePaused(current, total),
      StreamingPhase.finished => l10n.phaseFinished,
      StreamingPhase.error => l10n.phaseError,
    };

    return Material(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            IconButton(
              key: const ValueKey('playPauseButton'),
              tooltip: _isPaused ? l10n.resume : l10n.pause,
              onPressed: _isActive ? onTogglePlayPause : null,
              icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    phaseText,
                    style: AppText.caption,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: LinearProgressIndicator(
                      value: service.progress,
                      minHeight: 5,
                      backgroundColor: AppColors.hairline,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const ValueKey('stopButton'),
              tooltip: AppLocalizations.of(context).stop,
              onPressed: _isActive ? onStop : null,
              icon: const Icon(Icons.stop),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}
