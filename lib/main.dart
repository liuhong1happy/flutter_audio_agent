import 'package:flutter/material.dart';

import 'app.dart';
import 'app_dependencies.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dependencies = AppDependencies();
  await dependencies.init();

  runApp(TtsDemoApp(dependencies: dependencies));
}
