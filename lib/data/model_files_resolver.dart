/// 从解压后的模型目录中解析 sherpa-onnx 需要的文件路径。
///
/// sherpa-onnx 各模型包的文件名不完全一致(int8/fp32 变体、多 lexicon 等),
/// 因此采用"按模式扫描 + 优先 int8"的策略,而不是硬编码文件名。
/// 按 [ModelKind] 分支,区分 TTS / ASR / 声纹·VAD / Pocket 克隆的完整性。
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:flutter_tts_demo/data/models/tts_model.dart';

/// PocketTTS 克隆模型的 7 个文件路径。
class PocketModelPaths {
  const PocketModelPaths({
    required this.lmFlow,
    required this.lmMain,
    required this.encoder,
    required this.decoder,
    required this.textConditioner,
    required this.vocabJson,
    required this.tokenScoresJson,
  });

  final String lmFlow;
  final String lmMain;
  final String encoder;
  final String decoder;
  final String textConditioner;
  final String vocabJson;
  final String tokenScoresJson;

  bool get isComplete => lmFlow.isNotEmpty &&
      lmMain.isNotEmpty &&
      encoder.isNotEmpty &&
      decoder.isNotEmpty &&
      textConditioner.isNotEmpty &&
      vocabJson.isNotEmpty &&
      tokenScoresJson.isNotEmpty;
}

/// Transducer ASR(X-ASR / Zipformer)的三个模型文件。
class TransducerModelPaths {
  const TransducerModelPaths({
    required this.encoder,
    required this.decoder,
    required this.joiner,
  });

  final String encoder;
  final String decoder;
  final String joiner;

  bool get isComplete =>
      encoder.isNotEmpty && decoder.isNotEmpty && joiner.isNotEmpty;
}

/// 解析后的模型文件绝对路径集合。
class ResolvedModelPaths {
  const ResolvedModelPaths({
    required this.rootDir,
    this.modelPath,
    this.tokensPath,
    this.lexiconPath,
    this.voicesPath,
    this.dataDir,
    this.ruleFsts = const [],
    this.kind = ModelKind.tts,
    this.pocket,
    this.transducer,
    this.tokenizerJsonPath,
  });

  final String rootDir;
  final String? modelPath;
  final String? tokensPath;

  /// 文本嵌入用的 HF 分词器文件(`tokenizer.json`)。
  ///
  /// 与 ASR 的 [tokensPath] 是两回事:那个是 sherpa 的 `tokens.txt`,
  /// 这个是 HuggingFace `tokenizers` 格式的 JSON,由 `flutter_embedder` 内部解析。
  final String? tokenizerJsonPath;

  /// VITS:单个 lexicon.txt;Kokoro:`lexicon-us-en.txt,lexicon-zh.txt`。
  final String? lexiconPath;

  /// Kokoro 说话人嵌入文件 voices.bin。
  final String? voicesPath;

  /// Kokoro 的 espeak-ng-data 目录。
  final String? dataDir;

  final List<String> ruleFsts;

  final ModelKind kind;
  final PocketModelPaths? pocket;
  final TransducerModelPaths? transducer;

  /// 按种类判断关键文件是否齐全。
  bool get isComplete {
    switch (kind) {
      case ModelKind.tts:
        return modelPath != null &&
            tokensPath != null &&
            (lexiconPath != null || dataDir != null);
      case ModelKind.asrParaformer:
      case ModelKind.asrSenseVoice:
      case ModelKind.asrDolphin:
        return modelPath != null && tokensPath != null;
      case ModelKind.asrTransducer:
        return tokensPath != null && (transducer?.isComplete ?? false);
      case ModelKind.speaker:
      case ModelKind.vad:
        return modelPath != null;
      case ModelKind.pocket:
        return pocket?.isComplete ?? false;
      case ModelKind.embedding:
        return modelPath != null && tokenizerJsonPath != null;
    }
  }
}

class ModelFilesResolver {
  const ModelFilesResolver();

  ResolvedModelPaths? resolve(TtsModel model, String rootDir) {
    final dir = Directory(rootDir);
    if (!dir.existsSync()) return null;

    final allFiles = <File>[];
    final allDirs = <Directory>[];
    final walker = dir.listSync(recursive: true, followLinks: false);
    for (final entity in walker) {
      if (entity is File) allFiles.add(entity);
      if (entity is Directory) allDirs.add(entity);
    }

    String? find({required bool Function(String name) predicate}) {
      for (final f in allFiles) {
        if (predicate(p.basename(f.path))) return f.path;
      }
      return null;
    }

    switch (model.kind) {
      case ModelKind.tts:
        return _resolveTts(model, rootDir, allFiles, allDirs, find);
      case ModelKind.asrParaformer:
      case ModelKind.asrSenseVoice:
      case ModelKind.asrDolphin:
        return _resolveAsr(model, rootDir, find);
      case ModelKind.asrTransducer:
        return _resolveTransducer(model, rootDir, find);
      case ModelKind.speaker:
      case ModelKind.vad:
        return _resolveRaw(model, rootDir, find);
      case ModelKind.pocket:
        return _resolvePocket(model, rootDir, find);
      case ModelKind.embedding:
        return _resolveEmbedding(model, rootDir, find);
    }
  }

  /// 主模型文件:优先 int8,再 fp16,最后任意 .onnx。
  static String? _findModel(
    String? Function({required bool Function(String) predicate}) find,
  ) {
    return find(
          predicate: (name) =>
              name.endsWith('.onnx') && name.toLowerCase().contains('int8'),
        ) ??
        find(
          predicate: (name) =>
              name.endsWith('.onnx') && name.toLowerCase().contains('fp16'),
        ) ??
        find(predicate: (name) => name.endsWith('.onnx'));
  }

  ResolvedModelPaths _resolveTts(
    TtsModel model,
    String rootDir,
    List<File> allFiles,
    List<Directory> allDirs,
    String? Function({required bool Function(String) predicate}) find,
  ) {
    final modelPath = _findModel(find);
    final tokens = find(predicate: (name) => name == 'tokens.txt');

    final String? lexicon;
    if (model.family == TtsModelFamily.kokoro) {
      // Kokoro 需要 lexicon-us-en.txt 与 lexicon-zh.txt 一起。
      // ⚠️ 必须限定在 lexicon 文件内:包内还有 date-zh.fst / number-zh.fst /
      // phone-zh.fst,只按 `contains('zh')` 找会把规则 fst 当成中文词典传给引擎
      // (int8 包尤其明显),导致中文音素化静默错乱。
      final zh = find(
        predicate: (name) {
          final n = name.toLowerCase();
          return n.contains('lexicon') && n.contains('zh');
        },
      );
      final en = find(
        predicate: (name) =>
            name.contains('us-en') ||
            (name.contains('lexicon') && name.toLowerCase().contains('en')),
      );
      if (zh != null && en != null) {
        lexicon = '$en,$zh';
      } else {
        lexicon =
            find(predicate: (name) => name.toLowerCase().contains('lexicon'));
      }
    } else {
      lexicon = find(predicate: (name) => name == 'lexicon.txt');
    }

    final voices =
        find(predicate: (name) => name.toLowerCase() == 'voices.bin');

    String? dataDir;
    for (final d in allDirs) {
      final base = p.basename(d.path);
      if (base == 'espeak-ng-data' || base.contains('espeak')) {
        dataDir = d.path;
        break;
      }
    }

    // 归一化规则文件:优先模型声明,否则取目录下所有 .fst。
    final ruleFsts = <String>[];
    if (model.ruleFsts.isNotEmpty) {
      for (final wanted in model.ruleFsts) {
        final found = find(predicate: (name) => name == wanted);
        if (found != null) ruleFsts.add(found);
      }
    }
    if (ruleFsts.isEmpty) {
      for (final f in allFiles) {
        if (f.path.endsWith('.fst')) ruleFsts.add(f.path);
      }
    }

    return ResolvedModelPaths(
      rootDir: rootDir,
      modelPath: modelPath,
      tokensPath: tokens,
      lexiconPath: lexicon,
      voicesPath: voices,
      dataDir: dataDir,
      ruleFsts: ruleFsts,
      kind: ModelKind.tts,
    );
  }

  ResolvedModelPaths _resolveAsr(
    TtsModel model,
    String rootDir,
    String? Function({required bool Function(String) predicate}) find,
  ) {
    return ResolvedModelPaths(
      rootDir: rootDir,
      modelPath: _findModel(find),
      tokensPath: find(predicate: (name) => name == 'tokens.txt'),
      kind: model.kind,
    );
  }

  /// Transducer(X-ASR)按角色找三个文件。
  ///
  /// 包里 encoder/joiner 是 int8,而 decoder 常常只有 fp32 —— 不能套用
  /// `_findModel` 的"优先 int8"规则,否则只会找到 encoder 一个文件。
  /// 每个角色单独匹配,且仍优先 int8。
  ResolvedModelPaths _resolveTransducer(
    TtsModel model,
    String rootDir,
    String? Function({required bool Function(String) predicate}) find,
  ) {
    String role(String name) {
      final lowerName = name.toLowerCase();
      bool match(String file) {
        final f = file.toLowerCase();
        return f.endsWith('.onnx') && f.contains(lowerName);
      }

      return find(
            predicate: (file) =>
                match(file) && file.toLowerCase().endsWith('.int8.onnx'),
          ) ??
          find(predicate: match) ??
          '';
    }

    return ResolvedModelPaths(
      rootDir: rootDir,
      tokensPath: find(predicate: (name) => name == 'tokens.txt'),
      kind: ModelKind.asrTransducer,
      transducer: TransducerModelPaths(
        encoder: role('encoder'),
        decoder: role('decoder'),
        joiner: role('joiner'),
      ),
    );
  }

  ResolvedModelPaths _resolveRaw(
    TtsModel model,
    String rootDir,
    String? Function({required bool Function(String) predicate}) find,
  ) {
    // 裸文件优先按 rawFileName 精确匹配,回退任意 .onnx。
    final modelPath =
        (model.rawFileName != null
            ? find(predicate: (name) => name == model.rawFileName)
            : null) ??
        find(predicate: (name) => name.endsWith('.onnx'));
    return ResolvedModelPaths(
      rootDir: rootDir,
      modelPath: modelPath,
      kind: model.kind,
    );
  }

  /// 文本嵌入:需要 onnx + tokenizer.json。
  ///
  /// ⚠️ **断言不出现 `_data` 伴生文件**:`onnx-community` 那份模型是外置数据拆分格式
  /// (`.onnx` 仅 168KB 的图 + `.onnx_data` 23.8MB 的权重),只下 `.onnx` 会在加载时
  /// 失败且报错难读。我们一律用 `Xenova` 的单文件版;若目录里出现了 `_data` 文件,
  /// 说明模型来源被换成了拆分版 —— 这里直接判为**不完整**,让上层报错而不是带到运行时。
  ResolvedModelPaths _resolveEmbedding(
    TtsModel model,
    String rootDir,
    String? Function({required bool Function(String) predicate}) find,
  ) {
    final hasExternalData = find(predicate: (name) => name.endsWith('.onnx_data')) != null;
    if (hasExternalData) {
      return ResolvedModelPaths(rootDir: rootDir, kind: model.kind);
    }
    final modelPath = find(
          predicate: (name) => name == 'model_quantized.onnx',
        ) ??
        find(predicate: (name) => name.endsWith('.onnx'));
    final tokenizerJsonPath = find(predicate: (name) => name == 'tokenizer.json');
    return ResolvedModelPaths(
      rootDir: rootDir,
      modelPath: modelPath,
      tokenizerJsonPath: tokenizerJsonPath,
      kind: model.kind,
    );
  }

  ResolvedModelPaths _resolvePocket(
    TtsModel model,
    String rootDir,
    String? Function({required bool Function(String) predicate}) find,
  ) {
    // Pocket 的 encoder.onnx 是 fp32,勿用 int8 优先规则,按精确名匹配。
    final pocket = PocketModelPaths(
      lmFlow: find(predicate: (name) => name == 'lm_flow.int8.onnx') ?? '',
      lmMain: find(predicate: (name) => name == 'lm_main.int8.onnx') ?? '',
      encoder: find(predicate: (name) => name == 'encoder.onnx') ?? '',
      decoder: find(predicate: (name) => name == 'decoder.int8.onnx') ?? '',
      textConditioner:
          find(predicate: (name) => name == 'text_conditioner.onnx') ?? '',
      vocabJson: find(predicate: (name) => name == 'vocab.json') ?? '',
      tokenScoresJson:
          find(predicate: (name) => name == 'token_scores.json') ?? '',
    );
    return ResolvedModelPaths(
      rootDir: rootDir,
      pocket: pocket,
      kind: ModelKind.pocket,
    );
  }
}
