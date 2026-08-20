/// 朗读气泡列表(聊天式)。
///
/// **一次输入 = 一条气泡(整段文本)**,发送后输入框清空;再输入追加新气泡。
/// 列表可滚动,**永远把最后一条展示在最下方**。正在朗读的那条气泡
/// 内部做**逐词高亮**(卡拉OK式),点击气泡可重读该条。
library;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text.dart';
import '../../tts/text_chunker.dart';

class SpeakingBubblesView extends StatefulWidget {
  const SpeakingBubblesView({
    super.key,
    required this.utterances,
    required this.activeIndex,
    this.currentWordIndex = -1,
    this.autoScroll = true,
    this.onReplay,
  });

  /// 聊天气泡历史。
  final List<Utterance> utterances;

  /// 正在朗读的气泡下标(-1 = 无)。
  final int activeIndex;

  /// 当前正在朗读的词(该气泡整段文本内的全局下标,-1 = 无)。
  final int currentWordIndex;

  final bool autoScroll;

  /// 点击气泡回调(重读该条)。
  final void Function(int index)? onReplay;

  @override
  State<SpeakingBubblesView> createState() => _SpeakingBubblesViewState();
}

class _SpeakingBubblesViewState extends State<SpeakingBubblesView> {
  final ScrollController _scrollController = ScrollController();
  int _lastCount = 0;
  int _lastActiveIndex = -1;

  @override
  void didUpdateWidget(covariant SpeakingBubblesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 新增气泡或切到别的气泡时,滚动到底部展示最新一条。
    if (widget.autoScroll &&
        (widget.utterances.length != _lastCount ||
            widget.activeIndex != _lastActiveIndex)) {
      _lastCount = widget.utterances.length;
      _lastActiveIndex = widget.activeIndex;
      _scrollToBottom();
    }
  }

  Future<void> _scrollToBottom() async {
    if (!_scrollController.hasClients) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.utterances.isEmpty) {
      return const Center(
        child: Text('输入文本后点击"发送",这里会逐条显示朗读气泡。'),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      itemCount: widget.utterances.length,
      itemBuilder: (context, i) {
        final u = widget.utterances[i];
        final isActive = i == widget.activeIndex;
        return _Bubble(
          text: isActive ? u.normalizedText : u.originalText,
          words: isActive ? u.allWords : const <WordSpan>[],
          useWordHighlight: isActive && u.allWords.isNotEmpty,
          currentWordIndex: isActive ? widget.currentWordIndex : -1,
          isActive: isActive,
          onTap: widget.onReplay == null ? null : () => widget.onReplay!(i),
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.text,
    required this.words,
    required this.useWordHighlight,
    required this.currentWordIndex,
    required this.isActive,
    this.onTap,
  });

  final String text;
  final List<WordSpan> words;
  final bool useWordHighlight;
  final int currentWordIndex;
  final bool isActive;
  final VoidCallback? onTap;

  List<TextSpan> _buildSpans() {
    final spans = <TextSpan>[];
    var wordCount = 0;

    for (final w in words) {
      final isReal = !w.isSeparator;
      final wordIndex = isReal ? wordCount++ : -1;
      final isHighlight =
          useWordHighlight && isReal && wordIndex == currentWordIndex;

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
      } else if (!isActive) {
        style = AppText.body.copyWith(color: AppColors.inkSecondary);
      } else {
        style = AppText.body.copyWith(color: AppColors.inkPrimary);
      }
      spans.add(TextSpan(text: w.text, style: style));
    }

    // 词列表为空时回退整句。
    if (spans.isEmpty) {
      spans.add(TextSpan(
        text: text,
        style: useWordHighlight
            ? AppText.body.copyWith(
                color: AppColors.accent,
                fontWeight: FontWeight.w600,
                backgroundColor: AppColors.accentWeak,
              )
            : AppText.body,
      ));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final bg = isActive ? AppColors.surface : AppColors.surfaceSunken;

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
            border: isActive
                ? Border.all(color: AppColors.hairline, width: 1)
                : null,
            boxShadow: isActive ? AppShadow.e1 : null,
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
                  color: isActive ? AppColors.accent : AppColors.inkTertiary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
