/// i18n 本地化加载测试:验证 zh/en 语言包可加载且关键文案正确。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_tts_demo/l10n/app_localizations.dart';

void main() {
  test('AppLocalizations 支持 zh 与 en,默认回退中文', () async {
    final zh = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(zh.synthesizeTab, '合成');
    expect(zh.send, '发送');
    expect(zh.phasePlaying(1, 5), '播放中 1/5');

    final en = await AppLocalizations.delegate.load(const Locale('en'));
    expect(en.synthesizeTab, 'Synthesize');
    expect(en.send, 'Send');
    expect(en.phasePlaying(1, 5), 'Playing 1/5');
  });
}
