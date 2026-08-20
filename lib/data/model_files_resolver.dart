/// 从解压后的模型目录中解析 sherpa-onnx 需要的文件路径。
///
/// sherpa-onnx 各模型包的文件名不完全一致(int8/fp32 变体、多 lexicon 等),
/// 因此采用"按模式扫描 + 优先 int8"的策略,而不是硬编码文件名。
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/tts_model.dart';

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
  });

  final String rootDir;
  final String? modelPath;
  final String? tokensPath;

  /// VITS:单个 lexicon.txt;Kokoro:`lexicon-us-en.txt,lexicon-zh.txt`。
  final String? lexiconPath;

  /// Kokoro 说话人嵌入文件 voices.bin。
  final String? voicesPath;

  /// Kokoro 的 espeak-ng-data 目录。
  final String? dataDir;

  final List<String> ruleFsts;

  bool get isComplete =>
      modelPath != null && tokensPath != null && (lexiconPath != null || dataDir != null);
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

    // 主模型文件:优先 int8,再 fp16,最后任意 .onnx。
    final modelPath = find(
      predicate: (name) =>
          name.endsWith('.onnx') && name.toLowerCase().contains('int8'),
    ) ??
        find(
          predicate: (name) =>
              name.endsWith('.onnx') && name.toLowerCase().contains('fp16'),
        ) ??
        find(predicate: (name) => name.endsWith('.onnx'));

    final tokens = find(predicate: (name) => name == 'tokens.txt');

    final String? lexicon;
    if (model.family == TtsModelFamily.kokoro) {
      // Kokoro 需要 lexicon-us-en.txt 与 lexicon-zh.txt 一起。
      final zh = find(predicate: (name) => name.contains('zh'));
      final en = find(
        predicate: (name) =>
            name.contains('us-en') ||
            (name.contains('lexicon') && name.toLowerCase().contains('en')),
      );
      if (zh != null && en != null) {
        lexicon = '$en,$zh';
      } else {
        lexicon = find(predicate: (name) => name.toLowerCase().contains('lexicon'));
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
    );
  }
}
