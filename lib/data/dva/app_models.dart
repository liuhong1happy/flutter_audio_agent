/// flutter_dva 状态模型(本地持久化数据)。
///
/// - `settings`: 应用级 TTS/对话设置
/// - `downloads`: 已下载模型 id 集合
/// - `history`: 合成页聊天气泡历史
/// - `clones`: 声音克隆档案
/// - `voiceprints`: 声纹档案(含备注)
/// - `conversation`: 按说话人分桶的对话历史
///
/// 通过 [ReduxPersistor] 自动持久化到 SharedPreferences(key 前缀 `perist:`)。
library;

import 'package:flutter_dva/flutter_dva.dart';

/// 持久化的 TTS/对话设置状态。
class SettingsState extends DvaState {
  String? selectedModelId;
  int sid = 0;
  double speed = 1.0;
  double silenceScale = 0.2;
  int numThreads = 2;
  String mirrorPrefix = '';
  bool autoScroll = true;

  String llmBaseUrl = 'https://api.deepseek.com/v1';
  String llmApiKey = '';
  String llmModel = 'deepseek-v4-flash';
  String llmSystemPrompt = '';
  String? asrModelId;
  double voiceprintThreshold = 0.6;
  double vadThreshold = 0.5;
  double vadMinSilence = 0.5;
  double vadMaxSpeech = 15.0;
  String conversationVoiceType = 'model';
  String? conversationModelVoiceId;
  String? conversationCloneId;
  int conversationSid = 0;

  @override
  void fromJson(Map<String, dynamic> json) {
    selectedModelId = json['selectedModelId'] as String?;
    sid = json['sid'] as int? ?? 0;
    speed = (json['speed'] as num?)?.toDouble() ?? 1.0;
    silenceScale = (json['silenceScale'] as num?)?.toDouble() ?? 0.2;
    numThreads = json['numThreads'] as int? ?? 2;
    mirrorPrefix = json['mirrorPrefix'] as String? ?? '';
    autoScroll = json['autoScroll'] as bool? ?? true;
    llmBaseUrl = json['llmBaseUrl'] as String? ?? 'https://api.deepseek.com/v1';
    llmApiKey = json['llmApiKey'] as String? ?? '';
    llmModel = json['llmModel'] as String? ?? 'deepseek-v4-flash';
    llmSystemPrompt = json['llmSystemPrompt'] as String? ?? '';
    asrModelId = json['asrModelId'] as String?;
    voiceprintThreshold =
        (json['voiceprintThreshold'] as num?)?.toDouble() ?? 0.6;
    vadThreshold = (json['vadThreshold'] as num?)?.toDouble() ?? 0.5;
    vadMinSilence = (json['vadMinSilence'] as num?)?.toDouble() ?? 0.5;
    vadMaxSpeech = (json['vadMaxSpeech'] as num?)?.toDouble() ?? 15.0;
    conversationVoiceType = json['conversationVoiceType'] as String? ?? 'model';
    conversationModelVoiceId = json['conversationModelVoiceId'] as String?;
    conversationCloneId = json['conversationCloneId'] as String?;
    conversationSid = json['conversationSid'] as int? ?? 0;
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
        'llmBaseUrl': llmBaseUrl,
        'llmApiKey': llmApiKey,
        'llmModel': llmModel,
        'llmSystemPrompt': llmSystemPrompt,
        'asrModelId': asrModelId,
        'voiceprintThreshold': voiceprintThreshold,
        'vadThreshold': vadThreshold,
        'vadMinSilence': vadMinSilence,
        'vadMaxSpeech': vadMaxSpeech,
        'conversationVoiceType': conversationVoiceType,
        'conversationModelVoiceId': conversationModelVoiceId,
        'conversationCloneId': conversationCloneId,
        'conversationSid': conversationSid,
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
      'setLlmBaseUrl': (s, a) {
        final st = s.getState() as SettingsState;
        st.llmBaseUrl = a.payload as String? ?? 'https://api.deepseek.com/v1';
        s.setState(st);
        return s;
      },
      'setLlmApiKey': (s, a) {
        final st = s.getState() as SettingsState;
        st.llmApiKey = a.payload as String? ?? '';
        s.setState(st);
        return s;
      },
      'setLlmModel': (s, a) {
        final st = s.getState() as SettingsState;
        st.llmModel = a.payload as String? ?? 'deepseek-v4-flash';
        s.setState(st);
        return s;
      },
      'setLlmSystemPrompt': (s, a) {
        final st = s.getState() as SettingsState;
        st.llmSystemPrompt = a.payload as String? ?? '';
        s.setState(st);
        return s;
      },
      'setAsrModelId': (s, a) {
        final st = s.getState() as SettingsState;
        st.asrModelId = a.payload as String?;
        s.setState(st);
        return s;
      },
      'setVoiceprintThreshold': (s, a) {
        final st = s.getState() as SettingsState;
        st.voiceprintThreshold = (a.payload as num?)?.toDouble() ?? 0.6;
        s.setState(st);
        return s;
      },
      'setVadThreshold': (s, a) {
        final st = s.getState() as SettingsState;
        st.vadThreshold = (a.payload as num?)?.toDouble() ?? 0.5;
        s.setState(st);
        return s;
      },
      'setVadMinSilence': (s, a) {
        final st = s.getState() as SettingsState;
        st.vadMinSilence = (a.payload as num?)?.toDouble() ?? 0.5;
        s.setState(st);
        return s;
      },
      'setVadMaxSpeech': (s, a) {
        final st = s.getState() as SettingsState;
        st.vadMaxSpeech = (a.payload as num?)?.toDouble() ?? 15.0;
        s.setState(st);
        return s;
      },
      'setConversationVoiceModel': (s, a) {
        final st = s.getState() as SettingsState;
        final pair = a.payload as List<dynamic>? ?? [];
        st.conversationVoiceType = 'model';
        st.conversationModelVoiceId = pair.isNotEmpty ? pair[0] as String? : null;
        st.conversationSid = pair.length > 1 ? pair[1] as int? ?? 0 : 0;
        s.setState(st);
        return s;
      },
      'setConversationVoiceClone': (s, a) {
        final st = s.getState() as SettingsState;
        st.conversationVoiceType = 'clone';
        st.conversationCloneId = a.payload as String?;
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

/// 声音克隆档案(配置型)。
class ClonesState extends DvaState {
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

/// clones 模型。
class ClonesModel extends Model<ClonesState> {
  ClonesModel() {
    namespace = 'clones';
    state = StoreOfState<ClonesState>(state: ClonesState());
    reducers = {
      'setItems': (s, a) {
        final st = s.getState() as ClonesState;
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

/// 声纹档案(含备注)。
class VoiceprintsState extends DvaState {
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

/// voiceprints 模型。
class VoiceprintsModel extends Model<VoiceprintsState> {
  VoiceprintsModel() {
    namespace = 'voiceprints';
    state = StoreOfState<VoiceprintsState>(state: VoiceprintsState());
    reducers = {
      'setItems': (s, a) {
        final st = s.getState() as VoiceprintsState;
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
