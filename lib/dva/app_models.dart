/// flutter_dva 状态模型(本地持久化数据)。
///
/// - `settings`: 应用级 TTS 设置(模型选择/语速/静音/线程/镜像/自动滚动)
/// - `downloads`: 已下载模型 id 集合
///
/// 通过 [ReduxPersistor] 自动持久化到 SharedPreferences(key 前缀 `perist:`)。
library;

import 'package:flutter_dva/flutter_dva.dart';

/// 持久化的 TTS 设置状态。
class SettingsState extends DvaState {
  String? selectedModelId;
  int sid = 0;
  double speed = 1.0;
  double silenceScale = 0.2;
  int numThreads = 2;
  String mirrorPrefix = '';
  bool autoScroll = true;

  @override
  void fromJson(Map<String, dynamic> json) {
    selectedModelId = json['selectedModelId'] as String?;
    sid = json['sid'] as int? ?? 0;
    speed = (json['speed'] as num?)?.toDouble() ?? 1.0;
    silenceScale = (json['silenceScale'] as num?)?.toDouble() ?? 0.2;
    numThreads = json['numThreads'] as int? ?? 2;
    mirrorPrefix = json['mirrorPrefix'] as String? ?? '';
    autoScroll = json['autoScroll'] as bool? ?? true;
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'selectedModelId': selectedModelId,
        'sid': sid,
        'speed': speed,
        'silenceScale': silenceScale,
        'numThreads': numThreads,
        'mirrorPrefix': mirrorPrefix,
        'autoScroll': autoScroll,
      };
}

/// settings 模型。
class SettingsModel extends Model<SettingsState> {
  SettingsModel() {
    namespace = 'settings';
    state = StoreOfState<SettingsState>(state: SettingsState());
    reducers = {
      'selectModel': (s, a) {
        final st = s.getState() as SettingsState;
        st.selectedModelId = a.payload as String?;
        s.setState(st);
        return s;
      },
      'setSid': (s, a) {
        final st = s.getState() as SettingsState;
        st.sid = a.payload as int? ?? 0;
        s.setState(st);
        return s;
      },
      'setSpeed': (s, a) {
        final st = s.getState() as SettingsState;
        st.speed = (a.payload as num?)?.toDouble() ?? 1.0;
        s.setState(st);
        return s;
      },
      'setSilenceScale': (s, a) {
        final st = s.getState() as SettingsState;
        st.silenceScale = (a.payload as num?)?.toDouble() ?? 0.2;
        s.setState(st);
        return s;
      },
      'setNumThreads': (s, a) {
        final st = s.getState() as SettingsState;
        st.numThreads = a.payload as int? ?? 2;
        s.setState(st);
        return s;
      },
      'setMirrorPrefix': (s, a) {
        final st = s.getState() as SettingsState;
        st.mirrorPrefix = a.payload as String? ?? '';
        s.setState(st);
        return s;
      },
      'setAutoScroll': (s, a) {
        final st = s.getState() as SettingsState;
        st.autoScroll = a.payload as bool? ?? true;
        s.setState(st);
        return s;
      },
    };
    effects = {};
  }
}

/// 已下载模型 id 集合。
class DownloadsState extends DvaState {
  List<String> downloadedIds = [];

  @override
  void fromJson(Map<String, dynamic> json) {
    downloadedIds =
        (json['downloadedIds'] as List<dynamic>?)?.cast<String>() ?? [];
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'downloadedIds': downloadedIds,
      };
}

/// downloads 模型。
class DownloadsModel extends Model<DownloadsState> {
  DownloadsModel() {
    namespace = 'downloads';
    state = StoreOfState<DownloadsState>(state: DownloadsState());
    reducers = {
      'setDownloaded': (s, a) {
        final st = s.getState() as DownloadsState;
        st.downloadedIds =
            (a.payload as List<dynamic>?)?.cast<String>() ?? [];
        s.setState(st);
        return s;
      },
    };
    effects = {};
  }
}

/// 聊天气泡历史(轻量):每条记录原始文本/归一化文本/毫秒级耗时统计。
///
/// 用于 App 重启后恢复气泡与耗时展示。
class HistoryState extends DvaState {
  List<Map<String, dynamic>> items = [];

  @override
  void fromJson(Map<String, dynamic> json) {
    items = (json['items'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        [];
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{'items': items};
}

/// history 模型。
class HistoryModel extends Model<HistoryState> {
  HistoryModel() {
    namespace = 'history';
    state = StoreOfState<HistoryState>(state: HistoryState());
    reducers = {
      'setItems': (s, a) {
        final st = s.getState() as HistoryState;
        st.items = (a.payload as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            [];
        s.setState(st);
        return s;
      },
    };
    effects = {};
  }
}
