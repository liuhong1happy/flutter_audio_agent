/// 朗读气泡列表(输入框在底部,上部为正在读的文本气泡条)。
///
/// 每个片段一个气泡;**正在朗读的词逐词高亮**(而非整句);点击气泡可
/// "重新读"该段;当前气泡自动滚动跟随。
library;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text.dart';
import '../../tts/text_chunker.dart';
import '../../tts/text_normalizer.dart';

class SpeakingBubblesView extends StatefulWidget {
  const SpeakingBubblesView({
    super.key,
    required this.segments,
    required this.currentSegment,
    required this.originalText,
    this.segmentWords = const [],
    this.currentWordIndex = -1,
    this.normalization,
    this.showNormalized = true,
    this.autoScroll = true,
    this.onReplaySegment,
  });

  final List<TtsSegment> segments;
  final int currentSegment;
  final String originalText;

  /// 每段的词级切分(与 [segments] 平行),用于逐词高亮。
  final List<List<WordSpan>> segmentWords;

  /// 当前正在朗读的词(当前片段内下标,-1 = 无)。
  final int currentWordIndex;

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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      itemCount: widget.segments.length,
      itemBuilder: (context, i) {
        final key = _itemKeys.putIfAbsent(i, () => GlobalKey());
        final isCurrent = i == widget.currentSegment;
        final isPast = i < widget.currentSegment && widget.currentSegment >= 0;
        final words = (i < widget.segmentWords.length)
            ? widget.segmentWords[i]
            : const <WordSpan>[];
        return _Bubble(
          key: key,
          text: _displayText(i),
          words: words,
          isCurrent: isCurrent,
          isPast: isPast,
          useWordHighlight: isCurrent && widget.showNormalized,
          currentWordIndex: isCurrent ? widget.currentWordIndex : -1,
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
    required this.words,
    required this.isCurrent,
    required this.isPast,
    required this.useWordHighlight,
    required this.currentWordIndex,
    this.onTap,
  });

  final String text;
  final List<WordSpan> words;
  final bool isCurrent;
  final bool isPast;
  final bool useWordHighlight;
  final int currentWordIndex;
  final VoidCallback? onTap;

  List<TextSpan> _buildSpans() {
    final spans = <TextSpan>[];
    var wordCount = 0;

    for (final w in words) {
      final isReal = !w.isSeparator;
      final wordIndex = isReal ? wordCount++ : -1;
      final isHighlight = useWordHighlight &&
          isReal &&
          wordIndex == currentWordIndex;

      TextStyle style;
      if (isHighlight) {
        style = AppText.body.copyWith(
          color: AppColors.accent,
          fontWeight: FontWeight.w600,
          backgroundColor: AppColors.accentWeak,
        );
      } else if (useWordHighlight && isReal && wordIndex < currentWordIndex) {
        // 已读词弱化。
        style = AppText.body.copyWith(color: AppColors.inkSecondary);
      } else if (isPast) {
        style = AppText.body.copyWith(color: AppColors.inkSecondary);
      } else {
        style = AppText.body.copyWith(color: AppColors.inkPrimary);
      }
      spans.add(TextSpan(text: w.text, style: style));
    }

    // 词列表为空(如原文视图)时回退整句。
    if (spans.isEmpty) {
      final style = isPast
          ? AppText.body.copyWith(color: AppColors.inkSecondary)
          : isCurrent
              ? AppText.body.copyWith(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                  backgroundColor: AppColors.accentWeak,
                )
              : AppText.body;
      spans.add(TextSpan(text: text, style: style));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    // 当前段仅保留极淡底色 + 发丝边框,主体高亮交给"正在读的词"。
    final bg = isCurrent
        ? AppColors.surface
        : isPast
            ? AppColors.surfaceSunken
            : AppColors.surface;

    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          key: onTap != null ? ValueKey('bubble_$text') : null,
          margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            border: isCurrent
                ? Border.all(color: AppColors.hairline, width: 1)
                : null,
            boxShadow: isCurrent ? AppShadow.e1 : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text.rich(
                  TextSpan(children: _buildSpans()),
                  style: AppText.body,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  Icons.replay_outlined,
                  size: 16,
                  color: isCurrent ? AppColors.accent : AppColors.inkTertiary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
