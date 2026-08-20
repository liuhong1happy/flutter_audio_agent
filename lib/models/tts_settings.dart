/// 应用级 TTS 设置(对应需求:界面上自定义应用特定的 TTS)。
///
/// 持久化到 shared_preferences;修改后通过 [TtsSettings] 的
/// [ChangeNotifier] 通知 UI 刷新,合成时由引擎/服务读取。
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TtsSettings extends ChangeNotifier {
  static const _kModelId = 'tts_settings.model_id';
  static const _kSid = 'tts_settings.sid';
  static const _kSpeed = 'tts_settings.speed';
  static const _kSilenceScale = 'tts_settings.silence_scale';
  static const _kNumThreads = 'tts_settings.num_threads';
  static const _kMirrorPrefix = 'tts_settings.mirror_prefix';
  static const _kAutoScroll = 'tts_settings.auto_scroll';

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

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedModelId = prefs.getString(_kModelId);
    _sid = prefs.getInt(_kSid) ?? 0;
    _speed = prefs.getDouble(_kSpeed) ?? 1.0;
    _silenceScale = prefs.getDouble(_kSilenceScale) ?? 0.2;
    _numThreads = prefs.getInt(_kNumThreads) ?? 2;
    _mirrorPrefix = prefs.getString(_kMirrorPrefix) ?? '';
    _autoScroll = prefs.getBool(_kAutoScroll) ?? true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kModelId, _selectedModelId ?? '');
    await prefs.setInt(_kSid, _sid);
    await prefs.setDouble(_kSpeed, _speed);
    await prefs.setDouble(_kSilenceScale, _silenceScale);
    await prefs.setInt(_kNumThreads, _numThreads);
    await prefs.setString(_kMirrorPrefix, _mirrorPrefix);
    await prefs.setBool(_kAutoScroll, _autoScroll);
  }

  Future<void> selectModel(String? modelId) async {
    _selectedModelId = modelId;
    _sid = 0;
    notifyListeners();
    await _save();
  }

  Future<void> setSid(int value) async {
    _sid = value;
    notifyListeners();
    await _save();
  }

  Future<void> setSpeed(double value) async {
    _speed = value;
    notifyListeners();
    await _save();
  }

  Future<void> setSilenceScale(double value) async {
    _silenceScale = value;
    notifyListeners();
    await _save();
  }

  Future<void> setNumThreads(int value) async {
    _numThreads = value;
    notifyListeners();
    await _save();
  }

  Future<void> setMirrorPrefix(String value) async {
    _mirrorPrefix = value;
    notifyListeners();
    await _save();
  }

  Future<void> setAutoScroll(bool value) async {
    _autoScroll = value;
    notifyListeners();
    await _save();
  }
}
