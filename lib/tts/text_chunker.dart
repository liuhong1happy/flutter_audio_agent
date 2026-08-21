/// 文本分句/分词(需求 4:模拟流式 TTS)。
///
/// 流程:按句末标点切句 → 合并过短句 → 超长句用 jieba 词边界二次切块。
/// 每个片段记录其在**归一化文本**中的起止区间,供朗读视图高亮与
/// 原文视图回映射使用。
library;

import 'package:jieba_flutter/analysis/jieba_segmenter.dart';

import 'text_normalizer.dart';

/// 一个待合成的文本片段。
class TtsSegment {
  const TtsSegment({
    required this.text,
    required this.start,
    required this.end,
  });

  /// 归一化后的朗读文本。
  final String text;

  /// 在归一化文本中的起始偏移。
  final int start;
  final int end;

  int get length => end - start;

  @override
  String toString() => 'TtsSegment[$start,$end): $text';
}

/// 一次输入(一条气泡)的完整记录。
///
/// 气泡 = 用户一次输入的**整段文本**,而不是逐句。合成时按句分块,
/// 但展示上是一条气泡,内部做逐词高亮。附处理耗时统计供气泡展示。
class Utterance {
  Utterance({
    required this.originalText,
    required this.normalizedText,
    required this.segments,
    required this.segmentWords,
    required this.allWords,
    this.normalization,
  });

  /// 用户原始输入。
  final String originalText;

  /// 归一化后(用于朗读展示与逐词高亮)。
  final String normalizedText;

  /// 分句结果。
  final List<TtsSegment> segments;

  /// 每段的词级切分(与 [segments] 平行,offset 基于段内文本)。
  final List<List<WordSpan>> segmentWords;

  /// 整段归一化文本的词级切分(offset 基于 [normalizedText])。
  final List<WordSpan> allWords;

  /// 归一化结果(原文视图回映射用)。
  final NormalizationResult? normalization;

  /// 处理耗时统计(合成过程中由服务填充)。
  final UtteranceStats stats = UtteranceStats();
}

/// 一次输入的处理耗时统计。
class UtteranceStats {
  /// 分词/分句处理时间。
  Duration tokenizeTime = Duration.zero;

  /// 首词音频返回时间(speak 开始 → 首个音频就绪)。
  Duration firstAudioLatency = Duration.zero;

  /// 文本 → 音频总合成时长(全部块合成完成)。
  Duration synthesisTotal = Duration.zero;

  /// 音频总播放时长(所有块音频时长之和)。
  Duration audioDuration = Duration.zero;

  /// 总处理时长 = 分词处理时间 + 文本转音频总时长。
  Duration get processingTotal => tokenizeTime + synthesisTotal;

  /// 是否已有统计。
  bool get hasData => tokenizeTime > Duration.zero || synthesisTotal > Duration.zero;

  /// 持久化用:统一毫秒级整数,避免浮点精度丢失。
  Map<String, int> toJson() => <String, int>{
        'tokenizeMs': tokenizeTime.inMilliseconds,
        'firstAudioMs': firstAudioLatency.inMilliseconds,
        'synthesisMs': synthesisTotal.inMilliseconds,
        'audioMs': audioDuration.inMilliseconds,
      };

  /// 从毫秒级数据恢复。
  void fromJson(Map<String, dynamic> json) {
    tokenizeTime =
        Duration(milliseconds: (json['tokenizeMs'] as num?)?.toInt() ?? 0);
    firstAudioLatency =
        Duration(milliseconds: (json['firstAudioMs'] as num?)?.toInt() ?? 0);
    synthesisTotal =
        Duration(milliseconds: (json['synthesisMs'] as num?)?.toInt() ?? 0);
    audioDuration =
        Duration(milliseconds: (json['audioMs'] as num?)?.toInt() ?? 0);
  }
}

/// 片段内的一个词(用于逐词高亮)。
class WordSpan {
  const WordSpan({
    required this.text,
    required this.start,
    required this.end,
    this.weight = 1,
  });

  final String text;

  /// 在片段文本中的起止偏移。
  final int start;
  final int end;

  /// 时长权重(按字符数);0 = 分隔符/标点,不高亮。
  final int weight;

  bool get isSeparator => weight <= 0;

  @override
  String toString() => 'WordSpan($text[$start,$end],w=$weight)';
}

class TextChunker {
  TextChunker({
    int maxSegmentLen = 60,
    int minSegmentLen = 6,
    this.enableJieba = true,
  })  : _maxLen = maxSegmentLen,
        _minLen = minSegmentLen;

  final int _maxLen;
  final int _minLen;

  /// 是否启用 jieba 长句切块(false 时跳过词典加载,测试用)。
  final bool enableJieba;

  JiebaSegmenter? _seg;
  bool _jiebaReady = false;

  /// 是否已加载 jieba 词典(约 5MB,惰性加载)。
  bool get jiebaReady => _jiebaReady;

  /// 加载 jieba 词典;失败则降级为纯字符切块。
  Future<void> ensureInitialized() async {
    if (!enableJieba) return;
    if (_jiebaReady) return;
    try {
      await JiebaSegmenter.init();
      _seg = JiebaSegmenter();
      _jiebaReady = true;
    } catch (_) {
      _jiebaReady = false;
    }
  }

  /// 句子结束标点(含换行)。
  static const String _sentenceBreaks = '。！？；;.!?…\n';

  static bool _isSentenceBreak(String ch) => _sentenceBreaks.contains(ch);

  static bool _isCjk(String ch) {
    final code = ch.codeUnitAt(0);
    return (code >= 0x4E00 && code <= 0x9FFF) ||
        (code >= 0x3400 && code <= 0x4DBF);
  }

  /// 把一句(已归一化)文本切分为词(供逐词高亮)。
  ///
  /// CJK 走 jieba 词边界;英文/数字按字母数字串;标点与空白作为
  /// 权重 0 的分隔符(不高亮)。返回的 [WordSpan] 覆盖整个文本。
  List<WordSpan> splitWords(String text) {
    final words = <WordSpan>[];
    var i = 0;
    while (i < text.length) {
      if (_isCjk(text[i])) {
        final runStart = i;
        while (i < text.length && _isCjk(text[i])) {
          i++;
        }
        final run = text.substring(runStart, i);
        var pos = runStart;
        final jw = _jiebaSplit(run);
        if (jw.isEmpty) {
          words.add(WordSpan(
            text: run,
            start: runStart,
            end: i,
            weight: run.length,
          ));
          pos = i;
        } else {
          for (final w in jw) {
            if (pos < i) {
              words.add(WordSpan(
                text: w,
                start: pos,
                end: pos + w.length,
                weight: w.length,
              ));
              pos += w.length;
            }
          }
        }
      } else {
        final runStart = i;
        while (i < text.length && !_isCjk(text[i])) {
          i++;
        }
        final run = text.substring(runStart, i);
        final re = RegExp(r'[A-Za-z0-9]+|[^\s]');
        var lastEnd = 0;
        for (final m in re.allMatches(run)) {
          if (m.start > lastEnd) {
            final sp = run.substring(lastEnd, m.start);
            words.add(WordSpan(
              text: sp,
              start: runStart + lastEnd,
              end: runStart + m.start,
              weight: 0,
            ));
          }
          final token = m.group(0)!;
          // 仅字母/数字串算"词";标点等其他字符为分隔符(weight 0,不高亮)。
          final isWord = RegExp(r'^[A-Za-z0-9]+$').hasMatch(token);
          words.add(WordSpan(
            text: token,
            start: runStart + m.start,
            end: runStart + m.end,
            weight: isWord ? token.length : 0,
          ));
          lastEnd = m.end;
        }
        if (lastEnd < run.length) {
          words.add(WordSpan(
            text: run.substring(lastEnd),
            start: runStart + lastEnd,
            end: runStart + run.length,
            weight: 0,
          ));
        }
      }
    }
    return words.isEmpty ? [WordSpan(text: text, start: 0, end: text.length)] : words;
  }

  List<String> _jiebaSplit(String cjkRun) {
    if (!_jiebaReady || _seg == null) return const [];
    try {
      return _seg!.sentenceProcess(cjkRun);
    } catch (_) {
      return const [];
    }
  }

  /// 对归一化文本分句。
  List<TtsSegment> chunk(String text) {
    final sentences = _splitSentences(text);
    final merged = _mergeShort(sentences);
    final out = <TtsSegment>[];
    for (final s in merged) {
      if (s.length > _maxLen && _jiebaReady && _seg != null) {
        out.addAll(_subsplit(s));
      } else {
        out.add(s);
      }
    }
    return out.isEmpty ? [TtsSegment(text: text, start: 0, end: text.length)] : out;
  }

  List<TtsSegment> _splitSentences(String text) {
    final out = <TtsSegment>[];
    final sb = StringBuffer();
    var start = 0;

    void flush(int end) {
      if (sb.isNotEmpty) {
        out.add(TtsSegment(text: sb.toString(), start: start, end: end));
        sb.clear();
      }
    }

    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      sb.write(ch);
      if (_isSentenceBreak(ch)) {
        flush(i + 1);
        start = i + 1;
      }
    }
    flush(text.length);
    return out;
  }

  List<TtsSegment> _mergeShort(List<TtsSegment> segments) {
    final out = <TtsSegment>[];
    for (final seg in segments) {
      if (out.isNotEmpty && seg.length < _minLen) {
        final last = out.removeLast();
        out.add(TtsSegment(
          text: '${last.text}${seg.text}',
          start: last.start,
          end: seg.end,
        ));
      } else {
        out.add(seg);
      }
    }
    return out;
  }

  /// 用 jieba 词边界把超长句切成 <= _maxLen 的片段。
  List<TtsSegment> _subsplit(TtsSegment seg) {
    final text = seg.text;
    final cuts = _safeCutPositions(text);
    if (cuts.length <= 1) {
      // 没有可切分边界,直接整段。
      return [seg];
    }

    final out = <TtsSegment>[];
    var chunkStart = 0;
    while (chunkStart < text.length) {
      var chunkEnd = chunkStart + _maxLen;
      if (chunkEnd >= text.length) {
        chunkEnd = text.length;
      } else {
        final cut = _lastCutAtOrBefore(cuts, chunkEnd);
        if (cut > chunkStart) chunkEnd = cut;
      }
      out.add(TtsSegment(
        text: text.substring(chunkStart, chunkEnd),
        start: seg.start + chunkStart,
        end: seg.start + chunkEnd,
      ));
      chunkStart = chunkEnd;
    }
    return out;
  }

  /// 收集"可以安全切分"的文本位置(词边界)。
  List<int> _safeCutPositions(String text) {
    final cuts = <int>[];
    var i = 0;
    while (i < text.length) {
      if (_isCjk(text[i])) {
        final runStart = i;
        while (i < text.length && _isCjk(text[i])) {
          i++;
        }
        final run = text.substring(runStart, i);
        var pos = runStart;
        var wordCount = 0;
        try {
          for (final word in _seg!.sentenceProcess(run)) {
            pos += word.length;
            cuts.add(pos);
            wordCount++;
          }
        } catch (_) {
          wordCount = 0;
        }
        if (wordCount == 0) cuts.add(i);
      } else {
        // 非 CJK(英文/数字):不在其中间切开,只在整段结束时切。
        while (i < text.length && !_isCjk(text[i])) {
          i++;
        }
        cuts.add(i);
      }
    }
    if (cuts.isEmpty || cuts.last != text.length) cuts.add(text.length);
    return cuts;
  }

  static int _lastCutAtOrBefore(List<int> cuts, int bound) {
    // cuts 升序,找 <= bound 的最大值。
    var lo = 0;
    var hi = cuts.length - 1;
    var result = cuts.first;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (cuts[mid] <= bound) {
        result = cuts[mid];
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return result;
  }
}
