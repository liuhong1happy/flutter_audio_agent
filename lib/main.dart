import 'package:flutter/material.dart';

import 'app.dart';
import 'app_dependencies.dart';
import 'dva/app_dva.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 先启动 flutter_dva(含 ReduxPersistor 持久化),再装配依赖。
  // deps 用 late 声明,让 dva.start 的 appCreator 能延迟引用它。
  late AppDependencies deps;
  final app = await initDva(appCreator: () => TtsDemoApp(dependencies: deps));

  deps = AppDependencies();
  await deps.init();

  return runApp(app());
}
