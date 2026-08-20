/// 模型下载抽象 + HTTP 实现。
///
/// 抽象成接口以便 patrol 集成测试注入假下载器,不依赖真实网络。
library;

import 'dart:io';

import 'package:dio/dio.dart';

/// 下载器接口。
abstract class ModelDownloader {
  /// 从 [url] 下载到 [savePath],通过 [onProgress] 回报
  /// `(已接收字节, 总字节)`(总字节未知时为 -1)。
  ///
  /// 支持 [cancelToken] 取消。
  Future<void> download({
    required String url,
    required String savePath,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  });
}

/// 基于 dio 的流式 HTTP 下载实现。
class HttpModelDownloader implements ModelDownloader {
  HttpModelDownloader({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              // 连接超时设短,便于多镜像快速回退;接收超时按数据块空闲计。
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(minutes: 10),
              sendTimeout: const Duration(minutes: 10),
            ));

  final Dio _dio;

  @override
  Future<void> download({
    required String url,
    required String savePath,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final file = File(savePath);
    await file.parent.create(recursive: true);
    await _dio.download(
      url,
      savePath,
      cancelToken: cancelToken,
      onReceiveProgress: onProgress,
    );
  }
}
