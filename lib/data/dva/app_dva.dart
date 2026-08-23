/// flutter_dva 初始化与访问。
///
/// 用法参考 masrobo neme-ai-app(lib/main.dart):全局 `Dva` 实例 +
/// `DvaOpts(initialState, models)`,在 `dva.start(app, callback, waitCallabck: true)`
/// 的回调中创建 [ReduxPersistor] 并 `persist()` 恢复持久化数据。
library;

import 'package:flutter_dva/flutter_dva.dart';

import 'package:flutter_tts_demo/data/app_dependencies.dart';
import 'package:flutter_tts_demo/data/dva/app_models.dart';

/// 全局 Dva 实例。
Dva dva = Dva(DvaOpts(
  initialState: <String, StoreOfState<dynamic>>{
    'settings': StoreOfState<SettingsState>(state: SettingsState()),
    'downloads': StoreOfState<DownloadsState>(state: DownloadsState()),
    'history': StoreOfState<HistoryState>(state: HistoryState()),
    'clones': StoreOfState<ClonesState>(state: ClonesState()),
    'voiceprints': StoreOfState<VoiceprintsState>(state: VoiceprintsState()),
  },
  models: <Model<dynamic>>[
    SettingsModel(),
    DownloadsModel(),
    HistoryModel(),
    ClonesModel(),
    VoiceprintsModel(),
  ],
));

/// 全局 store;未初始化时为 null(测试环境会走到该分支)。
Store? dvaStore() => dva.store;

/// 启动 Dva,在回调中接入持久化,返回 App 构建函数。
///
/// [appCreator] 会延迟到 `runApp(app())` 时才求值,因此允许引用
/// `late` 声明的依赖变量。
Future<WidgetCreatorFunction> initDva({
  required WidgetCreatorFunction appCreator,
}) {
  return dva.start(appCreator, () async {
    // 1. 数据持久化(settings / downloads / history)
    final persistor = ReduxPersistor(store: dva.store!, heartBeat: 450);
    await persistor.persist();
    // 2. 持久化恢复后,一起初始化应用依赖(单例)。
    await AppDependencies.instance.init();
  }, waitCallabck: true);
}
