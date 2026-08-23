import 'package:flutter/material.dart';

import 'package:flutter_tts_demo/app.dart';
import 'package:flutter_tts_demo/data/app_dependencies.dart';
import 'package:flutter_tts_demo/data/dva/app_dva.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 先启动 flutter_dva(含 ReduxPersistor),回调里在持久化恢复后
  // 统一初始化 AppDependencies 单例;appCreator 延迟引用同一单例。
  final app = await initDva(
    appCreator: () => TtsDemoApp(dependencies: AppDependencies.instance),
  );

  return runApp(app());
}
