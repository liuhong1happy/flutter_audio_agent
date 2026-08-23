/// 在线 LLM 客户端(OpenAI 兼容 SSE 流式)。
///
/// 本项目唯一联网组件:DeepSeek V4 Flash 的 `chat/completions` 流式接口。
/// ASR/TTS/克隆/声纹/VAD 全部离线。
library;

import 'dart:convert';

import 'package:dio/dio.dart';

/// 一条对话消息。
class LlmMessage {
  const LlmMessage({required this.role, required this.content});

  final String role; // 'system' | 'user' | 'assistant'
  final String content;

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
}

/// LLM 流式客户端接口(便于测试注入假实现)。
abstract class LlmClient {
  /// 发起流式对话,逐段产出 `choices[0].delta.content` 文本。
  Stream<String> streamChat({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<LlmMessage> messages,
    CancelToken? cancel,
  });
}

/// 基于 dio 的 SSE 流式实现。
class DioLlmClient implements LlmClient {
  DioLlmClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(minutes: 5),
            ));

  final Dio _dio;

  @override
  Stream<String> streamChat({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<LlmMessage> messages,
    CancelToken? cancel,
  }) async* {
    final url = baseUrl.endsWith('/')
        ? '${baseUrl}chat/completions'
        : '$baseUrl/chat/completions';

    final Response<ResponseBody> resp;
    try {
      resp = await _dio.post<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
        data: <String, dynamic>{
          'model': model,
          'messages': messages.map((m) => m.toJson()).toList(),
          'stream': true,
          'temperature': 0.7,
        },
        cancelToken: cancel,
      );
    } on DioException catch (e) {
      throw _friendlyError(e);
    }

    // 状态化 utf8.decoder:多字节 UTF-8 跨 TCP 块也能正确解码。
    final lines = resp.data!.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('data:')) continue;
      final data = trimmed.substring(5).trim();
      if (data == '[DONE]') break;
      if (data.isEmpty) continue; // 空 keepalive 行。
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final choices = json['choices'] as List<dynamic>?;
        if (choices == null || choices.isEmpty) continue;
        final content = (choices.first as Map<String, dynamic>)['delta']
            as Map<String, dynamic>?;
        final text = content?['content'];
        if (text is String && text.isNotEmpty) yield text;
      } catch (_) {
        // 忽略无法解析的 provider 负载行。
      }
    }
  }

  StateError _friendlyError(DioException e) {
    final code = e.response?.statusCode;
    switch (code) {
      case 401:
        return StateError('API Key 无效(401)');
      case 402:
        return StateError('账户余额不足(402)');
      case 429:
        return StateError('请求过于频繁(429)');
      default:
        return StateError('LLM 请求失败: ${e.message ?? e}');
    }
  }
}
