/// App 根组件:注入 Provider 依赖。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_dependencies.dart';
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
        title: 'Flutter TTS Demo',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const MainShell(),
      ),
    );
  }
}
