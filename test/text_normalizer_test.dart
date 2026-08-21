import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts_demo/tts/text_normalizer.dart';

void main() {
  group('TextNormalizer 基本数字', () {
    final n = TextNormalizer();

    test('整数转中文读法', () {
      expect(n.normalize('25').text, '二十五');
      expect(n.normalize('100').text, '一百');
      expect(n.normalize('200').text, '二百');
      expect(n.normalize('2000').text, '两千');
      expect(n.normalize('9999').text, '九千九百九十九');
    });

    test('小数转中文读法', () {
      expect(n.normalize('12.5').text, '十二点五');
      expect(n.normalize('1.05').text, '一点零五');
    });

    test('负数', () {
      expect(n.normalize('-5').text, '负五');
    });

    test('百分比', () {
      expect(n.normalize('50%').text, '百分之五十');
      expect(n.normalize('12.5%').text, '百分之十二点五');
    });

    test('年份逐位读法', () {
      expect(n.normalize('2024年').text, '二零二四年');
      expect(n.normalize('1999年').text, '一九九九年');
    });

    test('金额保留单位', () {
      expect(n.normalize('10元').text, '十元');
      expect(n.normalize('价格12.5元').text, '价格十二点五元');
    });

    test('电话上下文逐位读法', () {
      expect(n.normalize('拨打110').text, '拨打一一零');
      expect(n.normalize('电话13800138000').text, '电话一三八零零一三八零零零');
    });

    test('长数字串逐位读法', () {
      expect(n.normalize('12345678901').text, '一二三四五六七八九零一');
    });

    test('前导零按编码读', () {
      expect(n.normalize('007').text, '零零七');
    });

    test('全角数字转半角后归一化', () {
      expect(n.normalize('２５').text, '二十五');
    });

    test('sourceMap 可将归一化区间映射回原文', () {
      final r = n.normalize('今天是2024年');
      expect(r.text, '今天是二零二四年');
      // 归一化文本中"二零二四"对应原文 "2024" 起始下标 3。
      final (s, e) = r.toSourceRange(3, 7);
      expect(s, 3);
      expect(e, 7);
    });
  });

  group('TextNormalizer 边界格式', () {
    final n = TextNormalizer();

    test('日期 YYYY-MM-DD 读作年月日', () {
      expect(n.normalize('2026-09-06').text, '二零二六年九月六日');
    });

    test('连接号不读"负"(苏-27 / v1.10 的数字部分)', () {
      expect(n.normalize('苏-27').text, '苏二十七');
      expect(n.normalize('-5').text, '负五', reason: '真正的负号仍读"负"');
    });

    test('时间 12:35 读作几点几分;16:9 保持比值不误判', () {
      expect(n.normalize('12:35').text, '十二点三十五分');
      expect(n.normalize('16:9').text, '十六:九');
    });

    test('空格分隔的大数合并读法(186 420 / 金额)', () {
      expect(n.normalize('186 420 行').text, '十八万六千四百二十 行');
      expect(n.normalize('¥2 389 600.50 元').text,
          '¥二百三十八万九千六百点五 元');
    });

    test('年份容忍空格与区间(2026 年 / 2023-2026)', () {
      expect(n.normalize('2026 年').text, '二零二六年');
      expect(n.normalize('2023-2026').text, '二零二三至二零二六');
    });

    test('裸电话 3-4-4 逐位读;版本号按点读;百分比不被版本规则误吞', () {
      expect(n.normalize('138-1234-5678').text, '一三八一二三四五六七八');
      expect(n.normalize('V2.7.1').text, 'V二点七点一');
      expect(n.normalize('3.5%').text, '百分之三点五');
    });
  });
}
