/// LLM SSE 流式解析测试:mock dio 适配器喂 data:/[DONE]/UTF-8 跨块。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_tts_demo/utils/llm_client.dart';

/// 把指定字节流按 [chunks] 分块返回的假 dio 适配器。
class _ChunkedAdapter implements HttpClientAdapter {
  _ChunkedAdapter(this.chunks);

  final List<Uint8List> chunks;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody(
      Stream.fromIterable(chunks),
      200,
      headers: {
        Headers.contentTypeHeader: ['text/event-stream'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

DioLlmClient _client(List<Uint8List> chunks) {
  final dio = Dio();
  dio.httpClientAdapter = _ChunkedAdapter(chunks);
  return DioLlmClient(dio: dio);
}

String _sseContent(String content) =>
    'data: ${jsonEncode({'choices': [{'delta': {'content': content}}]})}\n\n';

Future<List<String>> _collect(Stream<String> stream) async {
  final out = <String>[];
  await for (final s in stream) {
    out.add(s);
  }
  return out;
}

void main() {
  test('解析 data: 行产出 delta.content', () async {
    final bytes = utf8.encode('${_sseContent('你好')}data: [DONE]\n\n');
    final client = _client([Uint8List.fromList(bytes)]);

    final parts = await _collect(client.streamChat(
      baseUrl: 'https://api.deepseek.com/v1',
      apiKey: 'k',
      model: 'deepseek-chat',
      messages: const [LlmMessage(role: 'user', content: 'hi')],
    ));
    expect(parts.join(), '你好');
  });

  test('[DONE] 终止,空 keepalive data: 跳过', () async {
    final body = '${_sseContent('a')}data: \n\ndata: [DONE]\n\n'
        '${_sseContent('b')}';
    final bytes = utf8.encode(body);
    final client = _client([Uint8List.fromList(bytes)]);

    final parts = await _collect(client.streamChat(
      baseUrl: 'https://api.deepseek.com/v1',
      apiKey: 'k',
      model: 'deepseek-chat',
      messages: const [LlmMessage(role: 'user', content: 'hi')],
    ));
    expect(parts.join(), 'a', reason: '[DONE] 之后不应再产出');
  });

  test('多字节 UTF-8 跨 TCP 块正确解码', () async {
    const content = '你好';
    final sse = '${_sseContent(content)}data: [DONE]\n\n';
    final bytes = utf8.encode(sse);
    // 把 '你'(3 字节)从中间切开,模拟跨块多字节字符。
    final contentStart = sse.indexOf(content);
    final prefixLen = utf8.encode(sse.substring(0, contentStart)).length;
    final youLen = utf8.encode('你').length;
    final split = prefixLen + youLen - 1;

    final client = _client([
      Uint8List.fromList(bytes.sublist(0, split)),
      Uint8List.fromList(bytes.sublist(split)),
    ]);

    final parts = await _collect(client.streamChat(
      baseUrl: 'https://api.deepseek.com/v1',
      apiKey: 'k',
      model: 'deepseek-chat',
      messages: const [LlmMessage(role: 'user', content: 'hi')],
    ));
    expect(parts.join(), content);
  });

  test('401 转友好错误', () async {
    final dio = Dio();
    dio.httpClientAdapter = _ThrowingAdapter(401);
    final client = DioLlmClient(dio: dio);

    await expectLater(
      client.streamChat(
        baseUrl: 'https://api.deepseek.com/v1',
        apiKey: 'k',
        model: 'deepseek-chat',
        messages: const [LlmMessage(role: 'user', content: 'hi')],
      ),
      emitsError(
        isA<StateError>().having((e) => e.message, 'message', contains('401')),
      ),
    );
  });
}

class _ThrowingAdapter implements HttpClientAdapter {
  _ThrowingAdapter(this.statusCode);

  final int statusCode;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(
      requestOptions: options,
      response: Response(requestOptions: options, statusCode: statusCode),
      type: DioExceptionType.badResponse,
    );
  }

  @override
  void close({bool force = false}) {}
}
