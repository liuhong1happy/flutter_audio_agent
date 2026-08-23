/// 声音克隆服务:克隆音档案 + PocketTTS 零样本合成。
///
/// 档案(参考 WAV 路径 + 采样率)经 dva `clones` 持久化;合成时
/// 按需懒加载 PocketTTS 引擎。
// ignore_for_file: prefer_initializing_formals
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dva/flutter_dva.dart';

import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/data/model_manager.dart';
import 'package:flutter_tts_demo/data/dva/app_dva.dart';
import 'package:flutter_tts_demo/data/dva/app_models.dart';
import 'package:flutter_tts_demo/data/models/tts_model.dart';
import 'package:flutter_tts_demo/utils/engines/pocket_tts_engine.dart';
import 'package:flutter_tts_demo/utils/engines/tts_engine.dart' show GeneratedAudioData;
import 'package:flutter_tts_demo/utils/wav_reader.dart';

/// 一个克隆音档案。
@immutable
class CloneVoiceProfile {
  const CloneVoiceProfile({
    required this.id,
    required this.name,
    required this.referenceWavPath,
    required this.sampleRate,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String referenceWavPath;
  final int sampleRate;
  final DateTime createdAt;
}

class VoiceCloningService extends ChangeNotifier {
  VoiceCloningService({
    required ModelManager modelManager,
    PocketTtsEngine? engine,
    WavReader? wavReader,
  })  : _modelManager = modelManager,
        _engine = engine ?? PocketTtsEngine(),
        _wavReader = wavReader ?? const WavReader();

  final ModelManager _modelManager;
  final PocketTtsEngine _engine;
  final WavReader _wavReader;

  final List<CloneVoiceProfile> _profiles = [];
  bool _loaded = false;

  List<CloneVoiceProfile> get profiles => List.unmodifiable(_profiles);

  CloneVoiceProfile? byId(String? id) {
    if (id == null) return null;
    for (final p in _profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 从 dva 恢复档案(不加载引擎)。
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final store = dvaStore();
    if (store == null) return;
    final s = store.getStateByKey<ClonesState>('clones');
    for (final item in s.items) {
      _profiles.add(CloneVoiceProfile(
        id: item['id'] as String? ?? '',
        name: item['name'] as String? ?? '',
        referenceWavPath: item['referenceWavPath'] as String? ?? '',
        sampleRate: item['sampleRate'] as int? ?? 16000,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          item['createdAt'] as int? ?? 0,
        ),
      ));
    }
    notifyListeners();
  }

  /// 确保 PocketTTS 引擎加载(按目录中的克隆模型)。
  Future<void> ensureLoaded() async {
    if (_engine.isLoaded) return;
    final model = ModelCatalog.byKind(ModelKind.pocket);
    if (model == null) return;
    if (!_modelManager.isDownloaded(model.id)) return;
    final paths = _modelManager.resolveModel(model);
    if (paths == null || paths.pocket == null || !paths.pocket!.isComplete) {
      return;
    }
    await _engine.load(paths: paths.pocket!, numThreads: 2);
  }

  /// 用已录好的参考 WAV 建立克隆音档案。
  Future<CloneVoiceProfile> createProfile(
    String name,
    String referenceWavPath,
  ) async {
    final wav = _wavReader.read(await File(referenceWavPath).readAsBytes());
    final now = DateTime.now();
    final profile = CloneVoiceProfile(
      id: '${now.microsecondsSinceEpoch}',
      name: name,
      referenceWavPath: referenceWavPath,
      sampleRate: wav.sampleRate,
      createdAt: now,
    );
    _profiles.add(profile);
    await _persist();
    notifyListeners();
    return profile;
  }

  Future<void> deleteProfile(String id) async {
    _profiles.removeWhere((p) => p.id == id);
    await _persist();
    notifyListeners();
  }

  /// 清空全部克隆档案(供清理缓存用)。
  Future<void> clearAll() async {
    _profiles.clear();
    await _persist();
    notifyListeners();
  }

  /// 以指定克隆音合成一句文本。
  Future<GeneratedAudioData> synthesize(
    String text,
    CloneVoiceProfile profile,
  ) async {
    await ensureLoaded();
    if (!_engine.isLoaded) {
      throw StateError('克隆引擎未就绪,请先下载声音克隆模型');
    }
    final wav = _wavReader.read(await File(profile.referenceWavPath).readAsBytes());
    return _engine.generate(
      text: text,
      refSamples: wav.samples,
      refRate: wav.sampleRate,
    );
  }

  Future<void> _persist() async {
    final store = dvaStore();
    if (store == null) return;
    await store.dispatch(
      DvaAction(
        'clones/setItems',
        _profiles.map((p) {
          return <String, dynamic>{
            'id': p.id,
            'name': p.name,
            'referenceWavPath': p.referenceWavPath,
            'sampleRate': p.sampleRate,
            'createdAt': p.createdAt.millisecondsSinceEpoch,
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
