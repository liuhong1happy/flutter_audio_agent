/// 主页:文本输入 → 归一化/分句 → 流式合成播放 → 朗读进度高亮。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/model_catalog.dart';
import '../data/model_manager.dart';
import '../models/tts_settings.dart';
import '../tts/tts_streaming_service.dart';
import 'model_manage_page.dart';
import 'tts_settings_page.dart';
import 'widgets/streaming_text_view.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _textController = TextEditingController();
  bool _showNormalized = true;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _onSpeakPressed(TtsStreamingService service) async {
    final text = _textController.text;
    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入文本')),
      );
      return;
    }
    await service.speak(text);
    // 若报错(未选模型/未下载),提示跳转。
    if (service.phase == StreamingPhase.error) {
      _showError(service.lastError);
    }
  }

  void _showError(String? error) {
    final msg = error ?? '发生错误';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        action: SnackBarAction(
          label: '去设置',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const TtsSettingsPage()),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<TtsStreamingService>();
    final settings = context.watch<TtsSettings>();
    final modelManager = context.watch<ModelManager>();

    final active = service.phase == StreamingPhase.synthesizing ||
        service.phase == StreamingPhase.playing ||
        service.phase == StreamingPhase.preparing;

    final selectedModel = ModelCatalog.byId(settings.selectedModelId);
    final modelReady = selectedModel != null &&
        modelManager.isDownloaded(selectedModel.id);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter TTS Demo'),
        actions: [
          IconButton(
            key: const ValueKey('modelManageButton'),
            tooltip: '模型管理',
            icon: const Icon(Icons.download_for_offline_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ModelManagePage()),
            ),
          ),
          IconButton(
            key: const ValueKey('settingsButton'),
            tooltip: 'TTS 设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TtsSettingsPage()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildStatusBar(service, modelReady),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    _buildInput(service, active),
                    const SizedBox(height: 8),
                    _buildViewControls(service),
                    const SizedBox(height: 8),
                    Expanded(
                      child: StreamingTextView(
                        segments: service.segments,
                        currentSegment: service.currentSegment,
                        originalText: service.rawText,
                        normalization: service.normalization,
                        showNormalized: _showNormalized,
                        autoScroll: settings.autoScroll,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar(TtsStreamingService service, bool modelReady) {
    final modelName = ModelCatalog.byId(
      Provider.of<TtsSettings>(context).selectedModelId,
    )?.displayName;

    final readyText = modelReady
        ? (modelName ?? '已选模型')
        : (modelName == null ? '未选择模型' : '所选模型未下载');
    final color = modelReady ? Colors.green : Colors.orange;

    final phaseText = switch (service.phase) {
      StreamingPhase.idle => '就绪',
      StreamingPhase.preparing => '准备中…',
      StreamingPhase.synthesizing => '合成中…',
      StreamingPhase.playing =>
        '播放中 ${service.currentSegment + 1}/${service.segments.length}',
      StreamingPhase.finished => '播放完成',
      StreamingPhase.error => '出错',
    };

    return Material(
      color: color.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(
              modelReady ? Icons.check_circle : Icons.warning_amber,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                readyText,
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              phaseText,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInput(TtsStreamingService service, bool active) {
    return Column(
      children: [
        TextField(
          key: const ValueKey('ttsInput'),
          controller: _textController,
          maxLines: 4,
          minLines: 2,
          decoration: InputDecoration(
            hintText: '输入要朗读的文本,例如:今天是2024年6月15号,价格12.5元,拨打110求助。',
            border: const OutlineInputBorder(),
            filled: true,
            suffixIcon: _textController.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _textController.clear();
                      setState(() {});
                    },
                  ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('speakButton'),
                onPressed: active
                    ? () async => service.stop()
                    : () => _onSpeakPressed(service),
                icon: Icon(active ? Icons.stop : Icons.play_arrow),
                label: Text(active ? '停止' : '合成并播放'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildViewControls(TtsStreamingService service) {
    if (service.segments.isEmpty) {
      return const SizedBox.shrink();
    }
    return Row(
      children: [
        const Text('显示:'),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('朗读文本'),
          selected: _showNormalized,
          onSelected: (_) => setState(() => _showNormalized = true),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('原文'),
          selected: !_showNormalized,
          onSelected: (_) => setState(() => _showNormalized = false),
        ),
        const Spacer(),
        Text(
          '进度 ${(service.progress * 100).round()}%',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
