/// 声纹服务:说话人注册/识别/删除 + 嵌入与备注持久化。
///
/// **档案按声纹模型分桶**:目录里可以同时存在多个声纹模型(ERes2Net、
/// CAMPPlus 等),它们的嵌入空间互不通用 —— 同一个人的两段嵌入在不同模型下
/// 不可比。因此每个档案都记着自己的 modelId,识别时对每个"有档案且已下载"
/// 的模型各跑一遍(各提取各的嵌入),多个模型给出不同结果时以"当前模型"为准。
///
/// 嵌入经 [SpeakerEngine] 提取与匹配,档案经 dva `voiceprints` 持久化,
/// 启动时 restore 回引擎对应模型的 manager。
///
/// ⚠️ 声纹不是安全因子:嵌入以明文 JSON 落盘(dva ReduxPersistor,非
/// Keystore/Keychain),3 秒录音即可重放通过,本 app 自带的 PocketTTS 克隆
/// 也能合成授权人声音。这里的一切只防误触,不挡有心人。
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
    required this.modelId,
    required this.name,
    required this.note,
    required this.embeddings,
    this.cloneId,
  });

  /// 产出这些嵌入的声纹模型 id(不同模型的嵌入不可比)。
  final String modelId;

  final String name;
  final String note;

  /// 注册时提取的嵌入(192 维)。
  final List<Float32List> embeddings;

  /// 绑定的克隆音 id(可选)。绑定后对话中此人说话就用这个克隆音回话。
  final String? cloneId;

  VoiceprintProfile copyWith({String? note, String? cloneId}) =>
      VoiceprintProfile(
        modelId: modelId,
        name: name,
        note: note ?? this.note,
        embeddings: embeddings,
        cloneId: cloneId ?? this.cloneId,
      );
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

  /// modelId → name → profile。
  final Map<String, Map<String, VoiceprintProfile>> _byModel = {};

  /// 是否已从 dva 读过一次 store(读的动作与模型无关,一次性把所有桶读进来)。
  bool _storeLoaded = false;

  /// 引擎里有该模型的槽、且该模型的档案已全部同步进去。
  final Set<String> _readyModelIds = {};

  // ── 模型解析 ────────────────────────────────────────────────────────

  /// 全部已下载的声纹模型(目录声明序)。
  List<TtsModel> get downloadedSpeakerModels => ModelCatalog.speakers()
      .where((m) => _modelManager.isDownloaded(m.id))
      .toList();

  /// 当前声纹模型 id:设置里的优先,不可用(不存在/未下载)则回落到首个已下载的。
  ///
  /// 返回 null 表示一个可用的声纹模型都没有。
  String? get currentModelId {
    final available = downloadedSpeakerModels;
    if (available.isEmpty) return null;
    final wanted = _settings.voiceprintModelId;
    if (wanted != null && available.any((m) => m.id == wanted)) return wanted;
    return available.first.id;
  }

  /// 模型显示名(供 UI 展示"当前声纹模型:X")。
  String? displayNameOf(String? modelId) =>
      modelId == null ? null : ModelCatalog.byId(modelId)?.displayName;

  // ── 档案视图 ────────────────────────────────────────────────────────

  /// 指定模型的全部档案。
  List<VoiceprintProfile> profilesOf(String modelId) =>
      List.unmodifiable(_byModel[modelId]?.values ?? const <VoiceprintProfile>[]);

  /// 当前模型的档案(UI 主视图)。
  List<VoiceprintProfile> get profiles {
    final mid = currentModelId;
    return mid == null ? const [] : profilesOf(mid);
  }

  bool get hasProfiles => profiles.isNotEmpty;

  /// 是否在任何模型下注册过声纹。
  ///
  /// 门禁的 fail-closed 判据必须用这个而不是 [hasProfiles]:因为 [identify]
  /// 是跨模型并集,只注册在另一个模型下的人照样能通过识别 —— 白名单实际是
  /// "任一模型下注册过的人",用当前模型的桶去判断会把能通过的人挡在门外。
  bool get hasAnyProfiles => _byModel.values.any((b) => b.isNotEmpty);

  /// 按名字查档案(对话流程用:取备注注入 LLM 上下文)。
  ///
  /// 优先当前模型桶;找不到再跨桶找。因为 [identify] 是跨模型并集
  /// ("在哪个模型下注册都认得出"),这里若只查当前桶,就会出现"认出了人
  /// 却不注入备注"的割裂。
  VoiceprintProfile? profileOf(String name) {
    final current = _byModel[currentModelId]?[name];
    if (current != null) return current;
    for (final bucket in _byModel.values) {
      final p = bucket[name];
      if (p != null) return p;
    }
    return null;
  }

  /// 指定模型已注册的人数。
  int countOf(String modelId) => _byModel[modelId]?.length ?? 0;

  /// 有档案的模型 id(用于提示"另一批人被藏起来了")。
  List<String> get modelIdsWithProfiles => _byModel.entries
      .where((e) => e.value.isNotEmpty)
      .map((e) => e.key)
      .toList();

  // ── 加载 ────────────────────────────────────────────────────────────

  /// 只把持久化档案读进内存(不需要模型,不需要引擎)。
  ///
  /// 与 [ensureLoaded] 分开:管理页要在冷启动时就显示已注册的人,
  /// 那时候未必有已下载的声纹模型、更不该为看列表去加载 onnx。
  Future<void> ensureStoreLoaded() async {
    if (_storeLoaded) return;
    _storeLoaded = true;
    final store = dvaStore();
    if (store == null) return;
    final s = store.getStateByKey<VoiceprintsState>('voiceprints');
    _byModel.addAll(decodeItems(s.items));
    notifyListeners();
  }

  /// 确保"当前模型"已加载且其档案已同步进引擎。
  Future<void> ensureLoaded() async {
    final mid = currentModelId;
    if (mid == null) return;
    await _ensureModelLoaded(mid);
  }

  /// 加载指定模型(幂等)并把它的档案同步进引擎。返回是否就绪。
  Future<bool> _ensureModelLoaded(String modelId) async {
    await ensureStoreLoaded();
    if (_readyModelIds.contains(modelId)) return true;
    final model = ModelCatalog.byId(modelId);
    if (model == null) return false;
    if (!_modelManager.isDownloaded(model.id)) return false;
    final paths = _modelManager.resolveModel(model);
    final modelPath = paths?.modelPath;
    if (modelPath == null) return false;

    // load 会重建该槽的 manager,同步必须发生在 load 之后(见 _syncProfilesFor)。
    _readyModelIds.remove(modelId);
    await _engine.load(modelId: modelId, modelPath: modelPath, numThreads: 1);
    await _syncProfilesFor(modelId);
    _readyModelIds.add(modelId);
    notifyListeners();
    return true;
  }

  /// 把某模型的全部档案灌进引擎里该模型的 manager。
  ///
  /// 只在该模型 load 之后调用:worker 的 load 无条件重建 manager,所以目标
  /// 永远是空 manager,全量写入不会重复注册。反过来,只要没有 load 就不能
  /// 同步 —— 重复 addMulti 的幂等性完全依赖这个顺序。
  Future<void> _syncProfilesFor(String modelId) async {
    for (final p in _byModel[modelId]?.values ?? const <VoiceprintProfile>[]) {
      await _engine.addMulti(
        modelId: modelId,
        name: p.name,
        embeddings: p.embeddings,
      );
    }
  }

  /// 用多段语音采样注册一位说话人。
  ///
  /// [modelId] 省略时用当前模型。同名重录会先删掉旧档案再注册。
  Future<void> enroll({
    required String name,
    required String note,
    required List<Float32List> samples,
    String? modelId,
  }) async {
    final mid = modelId ?? currentModelId;
    if (mid == null) {
      throw StateError('没有可用的声纹模型,请先下载声纹模型');
    }
    if (!await _ensureModelLoaded(mid)) {
      throw StateError('声纹引擎未就绪,请先下载声纹模型');
    }
    final embeddings = <Float32List>[];
    for (final s in samples) {
      final emb = await _engine.extract(
        modelId: mid,
        samples: s,
        sampleRate: 16000,
      );
      if (emb.isNotEmpty) embeddings.add(emb);
    }
    if (embeddings.isEmpty) {
      throw StateError('未能提取有效声纹,请录更长的语音');
    }

    final bucket = _byModel.putIfAbsent(mid, () => {});
    final existing = bucket[name];
    // 重名重录:显式先删,不依赖 sherpa 对重复名字的处理(可能随版本变:
    // 追加 / 返回 false / 覆盖)。
    if (existing != null) {
      await _engine.remove(modelId: mid, name: name);
    }
    await _engine.addMulti(modelId: mid, name: name, embeddings: embeddings);
    bucket[name] = VoiceprintProfile(
      modelId: mid,
      name: name,
      note: note,
      embeddings: embeddings,
      cloneId: existing?.cloneId,
    );
    await _persist();
    notifyListeners();
  }

  /// 识别一段语音属于哪位说话人(空 = 未知)。
  ///
  /// 对每个"有档案且已下载"的模型各跑一遍:每个模型有自己的嵌入空间,
  /// 同一个向量不能跨模型比较,所以必须各提取各的嵌入。多个模型匹配到不同
  /// 名字时以当前模型为准(同名字则直接返回)。
  Future<String> identify(Float32List samples, int sampleRate) async {
    final candidates = <String>[];
    for (final id in modelIdsWithProfiles) {
      final model = ModelCatalog.byId(id);
      if (model == null) continue;
      if (!_modelManager.isDownloaded(model.id)) continue;
      candidates.add(id);
    }
    if (candidates.isEmpty) return '';

    final matches = <String, String>{};
    for (final mid in candidates) {
      if (!await _ensureModelLoaded(mid)) continue;
      final emb = await _engine.extract(
        modelId: mid,
        samples: samples,
        sampleRate: sampleRate,
      );
      if (emb.isEmpty) continue;
      final name = await _engine.search(
        modelId: mid,
        embedding: emb,
        threshold: _settings.voiceprintThreshold,
      );
      if (name.isNotEmpty) matches[mid] = name;
    }
    if (matches.isEmpty) return '';
    final names = matches.values.toSet();
    if (names.length == 1) return names.first;
    final current = currentModelId;
    return (current != null ? matches[current] : null) ?? names.first;
  }

  /// 测试识别:返回与 [samples] 匹配的名字(空 = 未匹配),不落库。
  Future<String> identifyTest(Float32List samples, int sampleRate) =>
      identify(samples, sampleRate);

  Future<void> remove(String name, {String? modelId}) async {
    final mid = modelId ?? currentModelId;
    if (mid == null) return;
    _byModel[mid]?.remove(name);
    if (_engine.isModelLoaded(mid)) {
      await _engine.remove(modelId: mid, name: name);
    }
    await _persist();
    notifyListeners();
  }

  /// 给某位说话人绑定(或解绑)克隆音。绑定后对话中此人说话就用该克隆音回。
  Future<void> bindClone(String name, String? cloneId, {String? modelId}) async {
    final mid = modelId ?? currentModelId;
    if (mid == null) return;
    final p = _byModel[mid]?[name];
    if (p == null) return;
    _byModel[mid]![name] = VoiceprintProfile(
      modelId: p.modelId,
      name: p.name,
      note: p.note,
      embeddings: p.embeddings,
      cloneId: cloneId,
    );
    await _persist();
    notifyListeners();
  }

  /// 清空**全部**声纹档案(供清理缓存用,不只当前模型)。
  Future<void> clearAll() async {
    for (final entry in _byModel.entries) {
      if (!_engine.isModelLoaded(entry.key)) continue;
      for (final name in entry.value.keys) {
        await _engine.remove(modelId: entry.key, name: name);
      }
    }
    _byModel.clear();
    _readyModelIds.clear();
    await _persist();
    notifyListeners();
  }

  // ── 持久化 ──────────────────────────────────────────────────────────

  Future<void> _persist() async {
    final store = dvaStore();
    if (store == null) return;
    await store.dispatch(
      DvaAction('voiceprints/setItems', encodeProfiles(_byModel)),
    );
  }

  /// 解码持久化的 items。旧数据没有 modelId,一律归入
  /// [kLegacyVoiceprintModelId] —— 绝不能按目录声明序猜,否则有人重排目录
  /// 就会把老档案迁进另一套嵌入空间,识别结果静默变垃圾。
  static Map<String, Map<String, VoiceprintProfile>> decodeItems(
    List<Map<String, dynamic>> items,
  ) {
    final out = <String, Map<String, VoiceprintProfile>>{};
    for (final item in items) {
      final name = item['name'] as String? ?? '';
      if (name.isEmpty) continue;
      final embeds = (item['embeddings'] as List<dynamic>? ?? [])
          .map((e) => Float32List.fromList(
              (e as List<dynamic>).map((v) => (v as num).toDouble()).toList()))
          .toList();
      if (embeds.isEmpty) continue;
      final modelId = item['modelId'] as String? ?? kLegacyVoiceprintModelId;
      out.putIfAbsent(modelId, () => {})[name] = VoiceprintProfile(
        modelId: modelId,
        name: name,
        note: item['note'] as String? ?? '',
        embeddings: embeds,
        cloneId: item['cloneId'] as String?,
      );
    }
    return out;
  }

  static List<Map<String, dynamic>> encodeProfiles(
    Map<String, Map<String, VoiceprintProfile>> byModel,
  ) =>
      [
        for (final bucket in byModel.values)
          for (final p in bucket.values)
            <String, dynamic>{
              'modelId': p.modelId,
              'name': p.name,
              'note': p.note,
              'cloneId': p.cloneId,
              'embeddings': p.embeddings.map((e) => e.toList()).toList(),
            },
      ];

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }
}
