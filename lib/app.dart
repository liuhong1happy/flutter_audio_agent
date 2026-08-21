/// App 根组件:注入 Provider 依赖。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_dependencies.dart';
import 'l10n/app_localizations.dart';
import 'theme/app_theme.dart';
import 'ui/main_shell.dart';

class TtsDemoApp extends StatelessWidget {
  const TtsDemoApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: dependencies.settings),
        ChangeNotifierProvider.value(value: dependencies.modelManager),
        ChangeNotifierProvider.value(value: dependencies.streamingService),
      ],
      child: MaterialApp(
        // title 为 OS 任务管理器名称,品牌名无需随语言变化;
        // 且此处位于 Localizations 之上,不能用 of(context) 取本地化文本。
        title: 'Flutter TTS Demo',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        // 本地化:跟随系统语言(zh/en),回退中文。
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const MainShell(),
      ),
    );
  }
}
