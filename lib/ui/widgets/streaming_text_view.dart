/// 朗读进度视图(需求 7)。
///
/// 以"字幕行"形式渲染全部分段:正在朗读的片段高亮 + 粗体,
/// 已读片段弱化,并支持自动滚动跟随。可切换"朗读视图"(显示
/// 归一化后文本)与"原文视图"(高亮映射回原始输入)。
library;

import 'package:flutter/material.dart';

import '../../tts/text_chunker.dart';
import '../../tts/text_normalizer.dart';

class StreamingTextView extends StatefulWidget {
  const StreamingTextView({
    super.key,
    required this.segments,
    required this.currentSegment,
    required this.originalText,
    this.normalization,
    this.showNormalized = true,
    this.autoScroll = true,
    this.highlightColor,
  });

  final List<TtsSegment> segments;
  final int currentSegment;
  final String originalText;
  final NormalizationResult? normalization;

  /// true = 朗读视图(归一化文本);false = 原文视图。
  final bool showNormalized;
  final bool autoScroll;
  final Color? highlightColor;

  @override
  State<StreamingTextView> createState() => _StreamingTextViewState();
}

class _StreamingTextViewState extends State<StreamingTextView> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  int _lastAnimatedIndex = -1;

  @override
  void didUpdateWidget(covariant StreamingTextView oldWidget) {
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
        if (start <= widget.originalText.length && end <= widget.originalText.length) {
          return widget.originalText.substring(start, end);
        }
      }
      return seg.text;
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
    final scheme = Theme.of(context).colorScheme;
    final highlight = widget.highlightColor ?? scheme.primaryContainer;
    final onHighlight = scheme.onPrimaryContainer;

    if (widget.segments.isEmpty) {
      return const Center(
        child: Text('输入文本后点击"合成并播放",这里会逐句高亮显示朗读进度。'),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < widget.segments.length; i++)
              _buildSegment(i, highlight, onHighlight),
          ],
        ),
      ),
    );
  }

  Widget _buildSegment(int index, Color highlight, Color onHighlight) {
    final key = _itemKeys.putIfAbsent(index, () => GlobalKey());
    final isCurrent = index == widget.currentSegment;
    final isPast = index < widget.currentSegment && widget.currentSegment >= 0;
    final text = _displayText(index);

    return AnimatedContainer(
      key: key,
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isCurrent ? highlight : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 16,
          height: 1.5,
          fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
          color: isCurrent
              ? onHighlight
              : isPast
                  ? Theme.of(context).disabledColor
                  : null,
        ),
      ),
    );
  }
}
