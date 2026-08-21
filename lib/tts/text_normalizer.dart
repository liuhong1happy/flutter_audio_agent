/// 中文文本归一化(TTS 前端)。
///
/// 基于用户选定的 `num2text` 库,把阿拉伯数字/金额/百分比/年份等
/// 转换为中文读法,并生成"归一化文本 ↔ 原文"的字符级映射,
/// 供朗读视图高亮与原文视图回映射使用。
///
/// 设计原则:被 App 归一化后的文本不再含阿拉伯数字,引擎的
/// ruleFsts 因此不会再重复归一化;电话号/长数字串则逐位朗读。
library;

import 'package:num2text/num2text.dart';

/// 归一化结果。
class NormalizationResult {
  const NormalizationResult({required this.text, required this.sourceMap});

  /// 归一化后的文本。
  final String text;

  /// 长度与 [text] 相同;`sourceMap[i]` 是 `text[i]` 对应原文的字符下标。
  final List<int> sourceMap;

  /// 把归一化文本区间 [start,end) 映射回原文区间。
  (int, int) toSourceRange(int start, int end) {
    if (text.isEmpty) return (0, 0);
    final s = start.clamp(0, text.length - 1);
    final e = end.clamp(s + 1, text.length);
    final srcStart = sourceMap[s];
    final srcEnd = sourceMap[e - 1] + 1;
    return (srcStart, srcEnd);
  }
}

class TextNormalizer {
  TextNormalizer({Num2Text? num2Text})
      : _num = num2Text ?? Num2Text(initialLang: Lang.ZH);

  final Num2Text _num;

  static const String _digitChars = '零一二三四五六七八九';

  static final RegExp _yearRe = RegExp(r'(\d{4})\s*(?=年)');
  static final RegExp _yearRangeRe = RegExp(r'(\d{4})-(\d{4})');
  static final RegExp _dateRe = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})');
  // 版本号:至少两个小数点(2.7.1),避免误伤小数(3.5)与百分比(3.5%)。
  static final RegExp _versionRe = RegExp(r'(\d+(?:\.\d+){2,})');
  static final RegExp _percentRe = RegExp(r'(\d+(?:\.\d+)?)%');
  static final RegExp _phoneContextRe = RegExp(
      r'(电话|拨打|手机|号码|请拨|拨|打给|打)\s*(\d{3,})');
  static final RegExp _barePhoneRe = RegExp(r'(\d{3})-(\d{4})-(\d{4})');
  // 支持"空格分隔的数字组"(如 186 420、¥2 389 600.50),空格/不间断空格。
  static final RegExp _numberRe =
      RegExp(r'(-?\d+(?:[  ]\d+)*(?:\.\d+)?)');
  static final RegExp _timeRe = RegExp(r'(\d{1,2}):(\d{2})');

  /// 全角字符 → 半角(数字/标点)。
  static String _toHalfWidth(String ch) {
    final code = ch.codeUnitAt(0);
    if (code >= 0xFF01 && code <= 0xFF5E) {
      return String.fromCharCode(code - 0xFEE0);
    }
    if (code == 0x3000) return ' '; // 全角空格
    return ch;
  }

  /// 是否 CJK 字符。
  static bool _isCjk(String ch) {
    final code = ch.codeUnitAt(0);
    return (code >= 0x4E00 && code <= 0x9FFF) ||
        (code >= 0x3400 && code <= 0x4DBF);
  }

  /// [from] 之后第一个非空白字符是否为 CJK(用于判断"数字后是否跟单位")。
  static bool _nextCjk(String src, int from) {
    var j = from;
    while (j < src.length && (src[j] == ' ' || src[j] == ' ')) {
      j++;
    }
    return j < src.length && _isCjk(src[j]);
  }

  NormalizationResult normalize(String input) {
    // 1. 全角 → 半角,保留 1:1 字符映射。
    final half = StringBuffer();
    final halfMap = <int>[];
    for (var k = 0; k < input.length; k++) {
      half.write(_toHalfWidth(input[k]));
      halfMap.add(k);
    }
    final src = half.toString();

    // 2. 扫描归一化。
    final sb = StringBuffer();
    final map = <int>[];
    var i = 0;

    while (i < src.length) {
      final matched = _matchAt(src, i);
      if (matched != null) {
        sb.write(matched.text);
        // 把替换结果的每个输出字符按比例映射到被替换的原文区间,
        // 使"原文视图"能高亮完整的数字/年份。
        final len = matched.end - matched.sourceIndex;
        for (var j = 0; j < matched.text.length; j++) {
          final halfIdx =
              matched.sourceIndex + (len * j ~/ matched.text.length);
          map.add(halfMap[halfIdx.clamp(0, src.length - 1)]);
        }
        i = matched.end;
      } else {
        sb.write(src[i]);
        map.add(halfMap[i]);
        i++;
      }
    }

    return NormalizationResult(text: sb.toString(), sourceMap: map);
  }

  _Match? _matchAt(String src, int i) {
    // 0. 日期:2026-09-06 → 二零二六年九月六日
    final date = _dateRe.matchAsPrefix(src, i);
    if (date != null) {
      final y = date.group(1)!;
      final m = int.parse(date.group(2)!);
      final d = int.parse(date.group(3)!);
      return _Match(
        text: '${_digitByDigit(y)}年${_toChineseNumber('$m')}月'
            '${_toChineseNumber('$d')}日',
        sourceIndex: i,
        end: date.end,
      );
    }

    // 1. 年份:2024年 → 二零二四年(容忍 `2024 年` 中间空格)
    final year = _yearRe.matchAsPrefix(src, i);
    if (year != null) {
      final digits = year.group(1)!;
      return _Match(
        text: _digitByDigit(digits),
        sourceIndex: i,
        end: year.end,
      );
    }

    // 1a. 年份区间:2023-2026 → 二零二三至二零二六
    final yearRange = _yearRangeRe.matchAsPrefix(src, i);
    if (yearRange != null) {
      return _Match(
        text: '${_digitByDigit(yearRange.group(1)!)}至'
            '${_digitByDigit(yearRange.group(2)!)}',
        sourceIndex: i,
        end: yearRange.end,
      );
    }

    // 1b. 版本号:2.7.1 → 二点七点一(两个以上小数点,避免误伤小数)
    final version = _versionRe.matchAsPrefix(src, i);
    if (version != null) {
      final parts = version
          .group(1)!
          .split('.')
          .map((p) => _toChineseNumber(p))
          .join('点');
      return _Match(
        text: parts,
        sourceIndex: i,
        end: version.end,
      );
    }

    // 2. 百分比:12.5% → 百分之十二点五
    final percent = _percentRe.matchAsPrefix(src, i);
    if (percent != null) {
      final value = percent.group(1)!;
      return _Match(
        text: '百分之${_toChineseNumber(value)}',
        sourceIndex: i,
        end: percent.end,
      );
    }

    // 3. 电话上下文:拨打 110 → 拨打 幺幺零(逐位)
    final phone = _phoneContextRe.matchAsPrefix(src, i);
    if (phone != null) {
      final ctx = phone.group(1)!;
      final digits = phone.group(2)!;
      return _Match(
        text: '$ctx${_digitByDigit(digits)}',
        sourceIndex: i,
        end: phone.end,
      );
    }

    // 3b. 裸电话:138-1234-5678 → 一三八一二三四五六七八(逐位,3-4-4 分组)
    final barePhone = _barePhoneRe.matchAsPrefix(src, i);
    if (barePhone != null) {
      final digits = barePhone.group(1)! +
          barePhone.group(2)! +
          barePhone.group(3)!;
      return _Match(
        text: _digitByDigit(digits),
        sourceIndex: i,
        end: barePhone.end,
      );
    }

    // 4. 时间:12:35 → 十二点三十五分(分钟为两位,避免误伤 16:9 比值)
    final time = _timeRe.matchAsPrefix(src, i);
    if (time != null) {
      final h = int.parse(time.group(1)!);
      final mi = int.parse(time.group(2)!);
      return _Match(
        text: '${_toChineseNumber('$h')}点${_toChineseNumber('$mi')}分',
        sourceIndex: i,
        end: time.end,
      );
    }

    // 5. 一般数字
    final num = _numberRe.matchAsPrefix(src, i);
    if (num != null) {
      return _matchNumber(src, num);
    }

    return null;
  }

  _Match? _matchNumber(String src, Match m) {
    // 去掉空格分隔的数字组(如 186 420、¥2 389 600.50)。
    final raw = m.group(1)!.replaceAll(RegExp(r'[  ]'), '');
    final hasMinus = raw.startsWith('-');
    // 只有"真正的负号"(句首/空白/括号后)才读"负";
    // 连接号(苏-27)不读负,直接去掉。
    final isNegative = hasMinus && _isLeadingMinus(src, m.start);
    final sign = isNegative ? '负' : '';
    final unsigned = hasMinus ? raw.substring(1) : raw;

    // 小数:一律按数量读(十二点五)。
    if (unsigned.contains('.')) {
      final text = sign + _toChineseNumber(unsigned);
      return _Match(text: text, sourceIndex: m.start, end: m.end);
    }

    final len = unsigned.length;

    // 下一个非空白字符是 CJK(单位/名词)→ 数量读法(容忍 `186 420 行` 的空格)。
    if (_nextCjk(src, m.end)) {
      final text = sign + _toChineseNumber(unsigned);
      return _Match(text: text, sourceIndex: m.start, end: m.end);
    }

    // 前导零或 >=5 位 → 逐位读(编码/号码)。
    final hasLeadingZero = len > 1 && unsigned.startsWith('0');
    if (hasLeadingZero || len >= 5) {
      final text = sign + _digitByDigit(unsigned);
      return _Match(text: text, sourceIndex: m.start, end: m.end);
    }

    // 普通数量。
    final text = sign + _toChineseNumber(unsigned);
    return _Match(text: text, sourceIndex: m.start, end: m.end);
  }

  /// `-` 前一个字符是空白/开头/开括号 → 真正的负号;否则为连接号。
  static bool _isLeadingMinus(String src, int start) {
    if (start <= 0) return true;
    final prev = src[start - 1];
    return prev == ' ' ||
        prev == '\t' ||
        prev == '\n' ||
        prev == '(' ||
        prev == '（' ||
        prev == '[' ||
        prev == '【';
  }

  String _toChineseNumber(String numberStr) {
    if (numberStr.startsWith('-')) {
      return '负${_toChineseNumber(numberStr.substring(1))}';
    }
    if (numberStr.contains('.')) {
      final v = double.tryParse(numberStr);
      if (v != null) return _num.convert(v);
    }
    final v = BigInt.tryParse(numberStr);
    if (v != null) return _num.convert(v);
    return numberStr;
  }

  static String _digitByDigit(String digits) {
    final sb = StringBuffer();
    for (final ch in digits.split('')) {
      if (ch == '+') {
        sb.write('');
      } else if (ch == '-') {
        sb.write('负');
      } else if (ch == '.') {
        sb.write('点');
      } else {
        sb.write(_digitChars[ch.codeUnitAt(0) - 0x30]);
      }
    }
    return sb.toString();
  }
}

class _Match {
  const _Match({required this.text, required this.sourceIndex, required this.end});

  final String text;

  /// 该替换对应原文的起始下标(整体映射用)。
  final int sourceIndex;
  final int end;
}
