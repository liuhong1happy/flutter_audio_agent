/// 朗读气泡列表(需求:输入框在底部,上部为正在读的文本气泡条)。
///
/// 每个片段一个气泡;正在朗读的气泡高亮;点击气泡可"重新读"该段;
/// 当前气泡自动滚动跟随。
library;

import 'package:flutter/material.dart';

import '../../tts/text_chunker.dart';
import '../../tts/text_normalizer.dart';

class SpeakingBubblesView extends StatefulWidget {
  const SpeakingBubblesView({
    super.key,
    required this.segments,
    required this.currentSegment,
    required this.originalText,
    this.normalization,
    this.showNormalized = true,
    this.autoScroll = true,
    this.onReplaySegment,
  });

  final List<TtsSegment> segments;
  final int currentSegment;
  final String originalText;
  final NormalizationResult? normalization;
  final bool showNormalized;
  final bool autoScroll;

  /// 点击气泡回调(重读该段)。
  final void Function(int index)? onReplaySegment;

  @override
  State<SpeakingBubblesView> createState() => _SpeakingBubblesViewState();
}

class _SpeakingBubblesViewState extends State<SpeakingBubblesView> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  int _lastAnimatedIndex = -1;

  @override
  void didUpdateWidget(covariant SpeakingBubblesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoScroll &&
        widget.currentSegment != _lastAnimatedIndex &&
        widget.currentSegment >= 0) {
      _lastAnimatedIndex = widget.currentSegment;
      _scrollToCurrent();
    }
  }

  Future<void> _scrollToCurrent() async {
    final key = _itemKeys[widget.currentSegment];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!ctx.mounted) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      alignment: 0.1,
    );
  }

  String _displayText(int index) {
    final seg = widget.segments[index];
    if (!widget.showNormalized) {
      final norm = widget.normalization;
      if (norm != null) {
        final (start, end) = norm.toSourceRange(seg.start, seg.end);
        if (start <= widget.originalText.length &&
            end <= widget.originalText.length) {
          return widget.originalText.substring(start, end);
        }
      }
    }
    return seg.text;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.segments.isEmpty) {
      return const Center(
        child: Text('输入文本后点击"发送",这里会逐句显示朗读气泡。'),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: widget.segments.length,
      itemBuilder: (context, i) {
        final key = _itemKeys.putIfAbsent(i, () => GlobalKey());
        final isCurrent = i == widget.currentSegment;
        final isPast = i < widget.currentSegment && widget.currentSegment >= 0;
        return _Bubble(
          key: key,
          text: _displayText(i),
          isCurrent: isCurrent,
          isPast: isPast,
          onTap: widget.onReplaySegment == null
              ? null
              : () => widget.onReplaySegment!(i),
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.text,
    required this.isCurrent,
    required this.isPast,
    this.onTap,
  });

  final String text;
  final bool isCurrent;
  final bool isPast;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = isCurrent
        ? scheme.primaryContainer
        : isPast
            ? scheme.surfaceContainerHighest
            : scheme.surfaceContainerLow;
    final fg = isCurrent ? scheme.onPrimaryContainer : scheme.onSurface;

    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          key: onTap != null ? ValueKey('bubble_$text') : null,
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            border: isCurrent ? Border.all(color: scheme.primary, width: 1.2) : null,
            boxShadow: isCurrent
                ? [BoxShadow(color: scheme.primary.withValues(alpha: 0.25), blurRadius: 8)]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.5,
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                    color: fg,
                  ),
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.replay,
                  size: 16,
                  color: isCurrent ? scheme.primary : scheme.outline,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
