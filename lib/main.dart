import 'package:flutter/material.dart';

import 'app.dart';
import 'app_dependencies.dart';
import 'dva/app_dva.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 先启动 flutter_dva(含 ReduxPersistor),回调里在持久化恢复后
  // 统一初始化 AppDependencies 单例;appCreator 延迟引用同一单例。
  final app = await initDva(
    appCreator: () => TtsDemoApp(dependencies: AppDependencies.instance),
  );

  return runApp(app());
}
