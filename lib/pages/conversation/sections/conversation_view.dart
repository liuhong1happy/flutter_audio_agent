/// 对话视图:状态胶囊 + 消息列表 + 底部控制/输入栏。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/utils/conversation_service.dart';

import '../components/control_bar.dart';
import '../components/message_list.dart';
import '../components/status_bar.dart';
import '../components/text_input_bar.dart';
import '../conversation_mode.dart';

class ConversationView extends StatelessWidget {
  const ConversationView({super.key, required this.service, required this.mode});

  final ConversationService service;
  final ConversationMode mode;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<TtsSettings>();

    return SafeArea(
      child: Column(
        children: [
          StatusBar(service: service, settings: settings),
          Expanded(
            child: MessageList(service: service, mode: mode),
          ),
          if (mode == ConversationMode.audio)
            ControlBar(service: service)
          else
            TextInputBar(service: service),
        ],
      ),
    );
  }
}
