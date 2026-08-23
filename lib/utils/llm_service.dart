/// LLM 服务:从设置取 baseUrl/apiKey/model,包装 [LlmClient] 的流式调用。
// ignore_for_file: prefer_initializing_formals
library;

import 'package:dio/dio.dart';

import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/utils/llm_client.dart';

class LlmService {
  LlmService({required TtsSettings settings, LlmClient? client})
      : _settings = settings,
        _client = client ?? DioLlmClient();

  final TtsSettings _settings;
  final LlmClient _client;

  /// 流式对话,逐段产出文本;空 key 直接报友好错误。
  Stream<String> streamChat(List<LlmMessage> messages, {CancelToken? cancel}) {
    if (_settings.llmApiKey.trim().isEmpty) {
      return Stream<String>.error(StateError('未配置 LLM API Key'));
    }
    return _client.streamChat(
      baseUrl: _settings.llmBaseUrl,
      apiKey: _settings.llmApiKey,
      model: _settings.llmModel,
      messages: messages,
      cancel: cancel,
    );
  }
}
