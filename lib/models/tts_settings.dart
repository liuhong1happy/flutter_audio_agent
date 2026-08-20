/// 应用级 TTS 设置(对应需求:界面上自定义应用特定的 TTS)。
///
/// 运行时用 [ChangeNotifier] 驱动 UI;持久化交给 flutter_dva
/// (`settings` 模型 + ReduxPersistor)。dva 未初始化(测试环境)时
/// 读写自动跳过,保持本地默认值。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_dva/flutter_dva.dart';

import '../dva/app_dva.dart';
import '../dva/app_models.dart';

class TtsSettings extends ChangeNotifier {
  /// 当前选中的模型 id(未选择为 null)。
  String? _selectedModelId;
  String? get selectedModelId => _selectedModelId;

  /// 说话人 sid(多音色模型有效)。
  int _sid = 0;
  int get sid => _sid;

  /// 语速 0.5 ~ 2.0。
  double _speed = 1.0;
  double get speed => _speed;

  /// 句间静音比例。
  double _silenceScale = 0.2;
  double get silenceScale => _silenceScale;

  /// 引擎推理线程数。
  int _numThreads = 2;
  int get numThreads => _numThreads;

  /// 下载镜像前缀(空 = 直连 GitHub;国内网络慢时可切换镜像)。
  String _mirrorPrefix = '';
  String get mirrorPrefix => _mirrorPrefix;

  /// 朗读视图是否自动滚动跟随。
  bool _autoScroll = true;
  bool get autoScroll => _autoScroll;

  /// 从 dva store 恢复持久化设置。
  Future<void> load() async {
    final store = dvaStore();
    if (store != null) {
      final s = store.getStateByKey<SettingsState>('settings');
      _selectedModelId = s.selectedModelId;
      _sid = s.sid;
      _speed = s.speed;
      _silenceScale = s.silenceScale;
      _numThreads = s.numThreads;
      _mirrorPrefix = s.mirrorPrefix;
      _autoScroll = s.autoScroll;
    }
    notifyListeners();
  }

  Future<void> _dispatch(String type, dynamic payload) async {
    final store = dvaStore();
    if (store != null) {
      await store.dispatch(DvaAction(type, payload));
    }
  }

  Future<void> selectModel(String? modelId) async {
    _selectedModelId = modelId;
    _sid = 0;
    notifyListeners();
    await _dispatch('settings/selectModel', modelId);
    await _dispatch('settings/setSid', 0);
  }

  Future<void> setSid(int value) async {
    _sid = value;
    notifyListeners();
    await _dispatch('settings/setSid', value);
  }

  Future<void> setSpeed(double value) async {
    _speed = value;
    notifyListeners();
    await _dispatch('settings/setSpeed', value);
  }

  Future<void> setSilenceScale(double value) async {
    _silenceScale = value;
    notifyListeners();
    await _dispatch('settings/setSilenceScale', value);
  }

  Future<void> setNumThreads(int value) async {
    _numThreads = value;
    notifyListeners();
    await _dispatch('settings/setNumThreads', value);
  }

  Future<void> setMirrorPrefix(String value) async {
    _mirrorPrefix = value;
    notifyListeners();
    await _dispatch('settings/setMirrorPrefix', value);
  }

  Future<void> setAutoScroll(bool value) async {
    _autoScroll = value;
    notifyListeners();
    await _dispatch('settings/setAutoScroll', value);
  }
}
