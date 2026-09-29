/// 大模型配置页:列表 + 编辑页(增删改、至少保留一条、切服务商替换地址与模型)。
///
/// 其中"切服务商后输入框里的地址/模型真的变了"这条,是
/// `TextFieldSetting.didUpdateWidget` 的回归防线 —— 没有它,自动填充在界面上
/// 是**看不见**的(controller 只在 initState 建过一次)。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_tts_demo/data/models/llm_config.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';
import 'package:flutter_tts_demo/pages/settings/sections/llm_section.dart';

/// 造一个已 load 过的设置(无 dva store → 会种出一条内置默认配置)。
Future<TtsSettings> _settings() async {
  SharedPreferences.setMockInitialValues({});
  final settings = TtsSettings();
  await settings.load();
  return settings;
}

Future<void> _pump(WidgetTester tester, TtsSettings settings) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<TtsSettings>.value(
      value: settings,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const LlmSection(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 读某个 key 的输入框当前文本。
String _fieldText(WidgetTester tester, String key) {
  final field = tester.widget<TextField>(
    find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(TextField),
    ),
  );
  return field.controller?.text ?? '';
}

/// 编辑页是 ListView,底部按钮在 600px 测试屏上会落在可视区外(懒加载不构建),
/// 交互前必须先滚到它。
Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.dragUntilVisible(
    target,
    find.byType(ListView).first,
    const Offset(0, -120),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('首次进入:恒有至少一条配置且已启用', (tester) async {
    final settings = await _settings();
    await _pump(tester, settings);

    expect(settings.llmConfigs.length, 1);
    expect(settings.activeLlmConfigId, settings.llmConfigs.first.id);
    expect(
      find.byKey(ValueKey('llmConfigRow_${settings.llmConfigs.first.id}')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('llmAddConfigButton')), findsOneWidget);
  });

  testWidgets('切服务商:地址与默认模型被替换,且输入框里看得见', (tester) async {
    final settings = await _settings();
    await _pump(tester, settings);

    // 进编辑页。
    await tester.tap(find.byKey(
      ValueKey('llmConfigRow_${settings.llmConfigs.first.id}'),
    ));
    await tester.pumpAndSettle();

    expect(_fieldText(tester, 'llmBaseUrlField'), kDefaultLlmBaseUrl);
    expect(_fieldText(tester, 'llmModelField'), kDefaultLlmModel);

    // 切到 Moonshot。
    await tester.tap(find.byKey(const ValueKey('llmProviderSelector')));
    await tester.pumpAndSettle();
    final moonshot = presetByName('Moonshot (Kimi)')!;
    await tester.tap(find.text(moonshot.name).last);
    await tester.pumpAndSettle();

    // 输入框必须真的跟着变(didUpdateWidget 生效)。
    expect(_fieldText(tester, 'llmBaseUrlField'), moonshot.baseUrl);
    expect(_fieldText(tester, 'llmModelField'), moonshot.model);
    // 名称没被用户改过 → 跟着换。
    expect(_fieldText(tester, 'llmConfigNameField'), moonshot.name);

    // 保存后落回设置。
    await tester.tap(find.byKey(const ValueKey('saveLlmConfigButton')));
    await tester.pumpAndSettle();
    expect(settings.llmBaseUrl, moonshot.baseUrl);
    expect(settings.llmModel, moonshot.model);
  });

  testWidgets('用户改过的名称不被切服务商覆盖', (tester) async {
    final settings = await _settings();
    await _pump(tester, settings);
    await tester.tap(find.byKey(
      ValueKey('llmConfigRow_${settings.llmConfigs.first.id}'),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('llmConfigNameField')),
      '我的配置',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('llmProviderSelector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('智谱 (GLM)').last);
    await tester.pumpAndSettle();

    expect(_fieldText(tester, 'llmConfigNameField'), '我的配置');
    expect(
      _fieldText(tester, 'llmBaseUrlField'),
      presetByName('智谱 (GLM)')!.baseUrl,
    );
  });

  testWidgets('只剩一条时不能删除;加到两条后可删', (tester) async {
    final settings = await _settings();
    await _pump(tester, settings);

    // 唯一的配置:编辑页里的删除按钮禁用。
    await tester.tap(find.byKey(
      ValueKey('llmConfigRow_${settings.llmConfigs.first.id}'),
    ));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const ValueKey('deleteLlmConfigButton')));
    final deleteBtn = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('deleteLlmConfigButton')),
    );
    expect(deleteBtn.onPressed, isNull, reason: '至少保留一条配置');
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 新增第二条(断言用 key 而非文案:测试环境 locale 是 en,中文文案断言会瞎)。
    await tester.tap(find.byKey(const ValueKey('llmAddConfigButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('saveLlmConfigButton')), findsOneWidget);
    // 新建的配置不带删除按钮(还没保存过)。
    expect(
      find.byKey(const ValueKey('deleteLlmConfigButton')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('saveLlmConfigButton')));
    await tester.pumpAndSettle();
    expect(settings.llmConfigs.length, 2);

    // 两条时删除可用,删掉一条后仍剩一条。
    final victim = settings.llmConfigs.last.id;
    await tester.tap(find.byKey(ValueKey('llmConfigRow_$victim')));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const ValueKey('deleteLlmConfigButton')));
    await tester.tap(find.byKey(const ValueKey('deleteLlmConfigButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirmDeleteLlmConfigButton')));
    await tester.pumpAndSettle();

    expect(settings.llmConfigs.length, 1);
    expect(settings.llmConfigs.any((c) => c.id == victim), isFalse);
  });

  testWidgets('切换启用项:兼容 getter 跟着走', (tester) async {
    final settings = await _settings();
    // 直接准备两条,避免依赖 UI 添加流程。
    await settings.upsertLlmConfig(const LlmConfig(
      id: 'b1',
      name: '备用',
      baseUrl: 'https://api.moonshot.cn/v1',
      apiKey: 'sk-b',
      model: 'moonshot-v1-8k',
    ));
    await _pump(tester, settings);

    await settings.setActiveLlmConfig('b1');
    await tester.pumpAndSettle();

    expect(settings.llmApiKey, 'sk-b');
    expect(settings.llmBaseUrl, 'https://api.moonshot.cn/v1');
    expect(settings.isLlmConfigured, isTrue);
  });
}
