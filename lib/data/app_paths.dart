/// 应用数据路径约定。
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppPaths {
  AppPaths._();

  /// 模型根目录:`文档目录/sherpa_tts/models`。
  static Future<Directory> modelsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'sherpa_tts', 'models'));
  }

  /// 模型下载/解压临时音频目录:`临时目录/tts_audio`。
  static Future<Directory> audioCacheDir() async {
    final tmp = await getTemporaryDirectory();
    return Directory(p.join(tmp.path, 'tts_audio'));
  }

  /// 克隆参考音频目录:`文档目录/sherpa_tts/clone_refs`(需跨重启持久)。
  static Future<Directory> cloneRefsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'sherpa_tts', 'clone_refs'));
  }

  /// 会话历史 SQLite 数据库文件路径(需跨重启持久)。
  static Future<String> conversationDbPath() async {
    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, 'sherpa_tts', 'conversation.db');
  }

  /// 清理时还需要一并清除的附加目录(应用缓存目录)。
  static Future<Directory> applicationCacheDir() =>
      getApplicationCacheDirectory();
}
