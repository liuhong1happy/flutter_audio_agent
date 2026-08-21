/// 合成 Tab(底部 Tab 方案 + 聊天式布局)。
///
/// 顶部:状态胶囊 + 视图切换;中部:朗读气泡列表(正在读的高亮、点击重读);
/// 底部:紧凑播放控制条 + 输入框。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/model_catalog.dart';
import '../data/model_manager.dart';
import '../l10n/app_localizations.dart';
import '../models/tts_settings.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import '../tts/tts_streaming_service.dart';
import 'widgets/speaking_bubbles_view.dart';

class SynthesizePage extends StatefulWidget {
  const SynthesizePage({super.key, this.onNavigateToSettings});

  /// 提示"去设置"时回调(由 MainShell 切换到设置 Tab)。
  final VoidCallback? onNavigateToSettings;

  @override
  State<SynthesizePage> createState() => _SynthesizePageState();
}

class _SynthesizePageState extends State<SynthesizePage> {
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 进入合成页时预加载所选模型(已加载则忽略);
    // 加载期间 modelLoading 为 true,发送按钮被禁用。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<TtsStreamingService>().prepareModel();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _onSpeakPressed(TtsStreamingService service) async {
    final text = _textController.text;
    if (text.trim().isEmpty) {
      _showMessage(AppLocalizations.of(context).emptyTextError);
      return;
    }
    await service.speak(text);
    if (service.phase == StreamingPhase.error) {
      _showError(service.lastError);
      return;
    }
    // 发送成功:清空输入框。
    _textController.clear();
    if (mounted) setState(() {});
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showError(String? error) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final msg = error ?? l10n.genericError;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        action: SnackBarAction(
          label: l10n.goSettings,
          onPressed: () => widget.onNavigateToSettings?.call(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<TtsStreamingService>();
    final settings = context.watch<TtsSettings>();
    final modelManager = context.watch<ModelManager>();
    final l10n = AppLocalizations.of(context);

    final selectedModel = ModelCatalog.byId(settings.selectedModelId);
    final modelReady =
        selectedModel != null && modelManager.isDownloaded(selectedModel.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.synthesizeTab),
        actions: [
          _StatusCapsule(
            ready: modelReady,
            modelName: selectedModel?.displayName,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SpeakingBubblesView(
                utterances: service.utterances,
                activeIndex: service.activeIndex,
                currentWordIndex: service.currentWordIndex,
                autoScroll: settings.autoScroll,
                onReplay: (i) => service.replayUtterance(i),
              ),
            ),
            _PlaybackControlBar(
              service: service,
              onTogglePlayPause: () async {
                if (service.phase == StreamingPhase.paused) {
                  await service.resume();
                } else if (service.phase == StreamingPhase.playing ||
                    service.phase == StreamingPhase.synthesizing) {
                  await service.pause();
                }
              },
              onStop: () => service.stop(),
            ),
            _InputBar(
              controller: _textController,
              onChange: () => setState(() {}),
              isEmpty: _textController.text.isEmpty,
              active: _isActivePhase(service.phase),
              loading: service.modelLoading,
              onSend: () => _onSpeakPressed(service),
              onStop: () => service.stop(),
            ),
          ],
        ),
      ),
    );
  }

}

/// 是否处于活跃播放态(用于按钮/控制条开关)。
bool _isActivePhase(StreamingPhase phase) =>
    phase == StreamingPhase.synthesizing ||
    phase == StreamingPhase.playing ||
    phase == StreamingPhase.preparing ||
    phase == StreamingPhase.paused;

/// 顶部状态胶囊:模型就绪状态 + 名称。
class _StatusCapsule extends StatelessWidget {
  const _StatusCapsule({required this.ready, this.modelName});

  final bool ready;
  final String? modelName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = ready ? AppColors.success : AppColors.warn;
    final text = ready
        ? (modelName ?? l10n.statusReady)
        : (modelName == null ? l10n.statusNoModel : l10n.statusNotDownloaded);
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Chip(
        avatar: Icon(
          ready ? Icons.check_circle_outline : Icons.warning_amber_outlined,
          size: 16,
          color: color,
        ),
        label: Text(
          text,
          style: AppText.caption.copyWith(color: color),
          overflow: TextOverflow.ellipsis,
        ),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// 紧凑播放控制条:播放/暂停、进度、停止。
class _PlaybackControlBar extends StatelessWidget {
  const _PlaybackControlBar({
    required this.service,
    required this.onTogglePlayPause,
    required this.onStop,
  });

  final TtsStreamingService service;
  final Future<void> Function() onTogglePlayPause;
  final VoidCallback onStop;

  bool get _isActive => _isActivePhase(service.phase);
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

/// 底部输入栏(需求:输入框在最底部)。
class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.onChange,
    required this.isEmpty,
    required this.active,
    required this.loading,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final VoidCallback onChange;
  final bool isEmpty;
  final bool active;

  /// 模型预加载中(发送按钮禁用)。
  final bool loading;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('ttsInput'),
                  controller: controller,
                  maxLines: 3,
                  minLines: 1,
                  onChanged: (_) => onChange(),
                  style: AppText.body,
                  decoration: InputDecoration(
                    hintText: l10n.inputHint,
                    isDense: true,
                    suffixIcon: isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              controller.clear();
                              onChange();
                            },
                          ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.icon(
                key: const ValueKey('speakButton'),
                onPressed: active ? onStop : (loading ? null : onSend),
                icon: Icon(
                  active
                      ? Icons.stop
                      : (loading ? Icons.hourglass_empty : Icons.send),
                ),
                label: Text(
                  active
                      ? l10n.stop
                      : (loading ? l10n.loadingModel : l10n.send),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
