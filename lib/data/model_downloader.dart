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

/// 基于 dio 的流式 HTTP 下载实现,支持 **Range 断点续传**(大模型 100~350MB)。
///
/// - 目标文件已存在部分内容时,自动带 `Range: bytes=<offset>-` 从断点续传。
/// - 服务端返回 206 → 增量追加;忽略 Range 返回 200(整包)→ 截断重下;
///   返回 416/412(不支持续传)→ 删除部分文件整包重下。
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

    // 已有部分文件 → 从该偏移续传。
    var offset = 0;
    if (await file.exists()) {
      offset = await file.length();
    }

    final headers = <String, dynamic>{};
    if (offset > 0) headers['Range'] = 'bytes=$offset-';

    final Response<ResponseBody> response;
    try {
      response = await _dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          headers: headers,
        ),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      // 416/412:服务端不支持续传 → 删除部分文件整包重下。
      final code = e.response?.statusCode;
      if ((code == 416 || code == 412) && offset > 0) {
        await file.delete();
        return download(
          url: url,
          savePath: savePath,
          onProgress: onProgress,
          cancelToken: cancelToken,
        );
      }
      rethrow;
    }

    final body = response.data!;

    // 服务端忽略 Range 返回 200(整包):丢弃已有部分,从头覆盖。
    final isPartial = body.statusCode == 206;
    var start = isPartial ? offset : 0;
    if (!isPartial && offset > 0) {
      await file.delete();
      offset = 0;
    }

    final total = _parseTotal(body.headers, offset);
    final raf = await file.open(mode: FileMode.append);
    try {
      var received = 0;
      await for (final chunk in body.stream) {
        if (cancelToken?.isCancelled ?? false) {
          throw DioException(
            requestOptions: RequestOptions(path: url),
            type: DioExceptionType.cancel,
          );
        }
        await raf.writeFrom(chunk);
        received += chunk.length;
        onProgress?.call(start + received, total ?? -1);
      }
    } finally {
      await raf.close();
    }
  }

  /// 从响应头解析总字节数:`Content-Range: bytes start-end/total` 优先,
  /// 其次 `Content-Length` + 已偏移量;无法解析返回 null。
  static int? _parseTotal(Map<String, List<String>> headers, int offset) {
    final contentRange = headers['content-range'];
    if (contentRange != null && contentRange.isNotEmpty) {
      final totalStr = contentRange.first.split('/').last.trim();
      final total = int.tryParse(totalStr);
      if (total != null) return total;
    }
    final contentLength = headers['content-length'];
    if (contentLength != null && contentLength.isNotEmpty) {
      final len = int.tryParse(contentLength.first);
      if (len != null) return offset + len;
    }
    return null;
  }
}
