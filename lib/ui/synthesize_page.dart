/// 合成 Tab(底部 Tab 方案 + 聊天式布局)。
///
/// 顶部:状态胶囊 + 视图切换;中部:朗读气泡列表(正在读的高亮、点击重读);
/// 底部:紧凑播放控制条 + 输入框。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/model_catalog.dart';
import '../data/model_manager.dart';
import '../models/tts_settings.dart';
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
  bool _showNormalized = true;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _onSpeakPressed(TtsStreamingService service) async {
    final text = _textController.text;
    if (text.trim().isEmpty) {
      _showMessage('请输入文本');
      return;
    }
    await service.speak(text);
    if (service.phase == StreamingPhase.error) {
      _showError(service.lastError);
    }
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showError(String? error) {
    if (!mounted) return;
    final msg = error ?? '发生错误';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        action: SnackBarAction(
          label: '去设置',
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

    final selectedModel = ModelCatalog.byId(settings.selectedModelId);
    final modelReady =
        selectedModel != null && modelManager.isDownloaded(selectedModel.id);

    return Scaffold(
      appBar: AppBar(
        title: const Text('合成'),
        actions: [
          _StatusCapsule(
            ready: modelReady,
            modelName: selectedModel?.displayName,
          ),
          if (service.segments.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: '显示方式',
              icon: const Icon(Icons.tune),
              onSelected: (v) => setState(
                () => _showNormalized = v == 'normalized',
              ),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'normalized',
                  child: Text('朗读文本'),
                ),
                const PopupMenuItem(value: 'original', child: Text('原文')),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SpeakingBubblesView(
                segments: service.segments,
                currentSegment: service.currentSegment,
                originalText: service.rawText,
                normalization: service.normalization,
                showNormalized: _showNormalized,
                autoScroll: settings.autoScroll,
                onReplaySegment: (i) => service.replaySegment(i),
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
    final color = ready ? Colors.green : Colors.orange;
    final text = ready
        ? (modelName ?? '已选模型')
        : (modelName == null ? '未选择模型' : '所选模型未下载');
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Chip(
        avatar: Icon(
          ready ? Icons.check_circle : Icons.warning_amber,
          size: 16,
          color: color,
        ),
        label: Text(
          text,
          style: TextStyle(fontSize: 12, color: color),
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
    final scheme = Theme.of(context).colorScheme;
    final phaseText = switch (service.phase) {
      StreamingPhase.idle => '就绪',
      StreamingPhase.preparing => '准备中…',
      StreamingPhase.synthesizing => '合成中…',
      StreamingPhase.playing =>
        '播放中 ${service.currentSegment + 1}/${service.segments.length}',
      StreamingPhase.paused =>
        '已暂停 ${service.currentSegment + 1}/${service.segments.length}',
      StreamingPhase.finished => '播放完成',
      StreamingPhase.error => '出错',
    };

    return Material(
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              key: const ValueKey('playPauseButton'),
              tooltip: _isPaused ? '继续' : '暂停',
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
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: service.progress,
                      minHeight: 5,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const ValueKey('stopButton'),
              tooltip: '停止',
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
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final VoidCallback onChange;
  final bool isEmpty;
  final bool active;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
                  decoration: InputDecoration(
                    hintText: '输入要朗读的文本…',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    isDense: true,
                    suffixIcon: isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              controller.clear();
                              onChange();
                            },
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const ValueKey('speakButton'),
                onPressed: active ? onStop : onSend,
                icon: Icon(active ? Icons.stop : Icons.send),
                label: Text(active ? '停止' : '发送'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
