/// 声纹服务:说话人注册/识别/删除 + 嵌入与备注持久化。
///
/// 嵌入经 [SpeakerEngine] 提取与匹配,档案经 dva `voiceprints` 持久化,
/// 启动时 restore 回引擎的 [sherpa_onnx.SpeakerEmbeddingManager]。
// ignore_for_file: prefer_initializing_formals
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_dva/flutter_dva.dart';

import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/data/model_manager.dart';
import 'package:flutter_tts_demo/data/dva/app_dva.dart';
import 'package:flutter_tts_demo/data/dva/app_models.dart';
import 'package:flutter_tts_demo/data/models/tts_model.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/utils/engines/speaker_engine.dart';

/// 一位已注册说话人。
@immutable
class VoiceprintProfile {
  const VoiceprintProfile({
    required this.name,
    required this.note,
    required this.embeddings,
  });

  final String name;
  final String note;

  /// 注册时提取的嵌入(192 维)。
  final List<Float32List> embeddings;
}

class VoiceprintService extends ChangeNotifier {
  VoiceprintService({
    required ModelManager modelManager,
    required TtsSettings settings,
    SpeakerEngine? engine,
  })  : _modelManager = modelManager,
        _settings = settings,
        _engine = engine ?? SpeakerEngine();

  final ModelManager _modelManager;
  final TtsSettings _settings;
  final SpeakerEngine _engine;

  final Map<String, VoiceprintProfile> _profiles = {};
  bool _loaded = false;

  List<VoiceprintProfile> get profiles => List.unmodifiable(_profiles.values);
  bool get hasProfiles => _profiles.isNotEmpty;

  VoiceprintProfile? profileOf(String name) => _profiles[name];

  /// 确保引擎加载(按目录中的声纹模型)并恢复已注册档案。
  Future<void> ensureLoaded() async {
    if (_engine.isLoaded) return;
    final model = ModelCatalog.byKind(ModelKind.speaker);
    if (model == null) return;
    if (!_modelManager.isDownloaded(model.id)) return;
    final paths = _modelManager.resolveModel(model);
    if (paths == null || paths.modelPath == null) return;

    await _engine.load(modelPath: paths.modelPath!, numThreads: 1);
    await _restoreFromStore();
  }

  Future<void> _restoreFromStore() async {
    if (_loaded) return;
    _loaded = true;
    final store = dvaStore();
    if (store == null) return;
    final s = store.getStateByKey<VoiceprintsState>('voiceprints');
    for (final item in s.items) {
      final name = item['name'] as String? ?? '';
      final note = item['note'] as String? ?? '';
      final embeds = (item['embeddings'] as List<dynamic>? ?? [])
          .map((e) => Float32List.fromList(
              (e as List<dynamic>).map((v) => (v as num).toDouble()).toList()))
          .toList();
      if (name.isEmpty || embeds.isEmpty) continue;
      _profiles[name] = VoiceprintProfile(name: name, note: note, embeddings: embeds);
      await _engine.addMulti(name, embeds);
    }
    notifyListeners();
  }

  /// 用多段语音采样注册一位说话人。
  Future<void> enroll({
    required String name,
    required String note,
    required List<Float32List> samples,
  }) async {
    await ensureLoaded();
    if (!_engine.isLoaded) {
      throw StateError('声纹引擎未就绪,请先下载声纹模型');
    }
    final embeddings = <Float32List>[];
    for (final s in samples) {
      final emb = await _engine.extract(s, 16000);
      if (emb.isNotEmpty) embeddings.add(emb);
    }
    if (embeddings.isEmpty) {
      throw StateError('未能提取有效声纹,请录更长的语音');
    }
    await _engine.addMulti(name, embeddings);
    _profiles[name] =
        VoiceprintProfile(name: name, note: note, embeddings: embeddings);
    await _persist();
    notifyListeners();
  }

  /// 识别一段语音属于哪位说话人(空 = 未知)。
  Future<String> identify(Float32List samples, int sampleRate) async {
    if (_profiles.isNotEmpty) {
      await ensureLoaded();
    } else {
      return '';
    }
    if (!_engine.isLoaded) return '';
    final emb = await _engine.extract(samples, sampleRate);
    if (emb.isEmpty) return '';
    return _engine.search(emb, _settings.voiceprintThreshold);
  }

  /// 测试识别:返回与 [samples] 匹配的名字(空 = 未匹配),不落库。
  Future<String> identifyTest(Float32List samples, int sampleRate) =>
      identify(samples, sampleRate);

  Future<void> remove(String name) async {
    _profiles.remove(name);
    if (_engine.isLoaded) {
      await _engine.remove(name);
    }
    await _persist();
    notifyListeners();
  }

  /// 清空全部声纹档案(供清理缓存用)。
  Future<void> clearAll() async {
    for (final name in _profiles.keys.toList()) {
      if (_engine.isLoaded) {
        await _engine.remove(name);
      }
    }
    _profiles.clear();
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final store = dvaStore();
    if (store == null) return;
    await store.dispatch(
      DvaAction(
        'voiceprints/setItems',
        _profiles.values.map((p) {
          return <String, dynamic>{
            'name': p.name,
            'note': p.note,
            'embeddings': p.embeddings
                .map((e) => e.toList())
                .toList(),
          };
        }).toList(),
      ),
    );
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }
}
