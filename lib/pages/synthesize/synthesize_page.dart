/// 合成 Tab(底部 Tab 方案 + 聊天式布局)。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tts_demo/components/speaking_bubbles_view.dart';
import 'package:flutter_tts_demo/data/model_catalog.dart';
import 'package:flutter_tts_demo/data/model_manager.dart';
import 'package:flutter_tts_demo/data/models/tts_model.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';
import 'package:flutter_tts_demo/utils/tts_streaming_service.dart';

import 'components/input_bar.dart';
import 'components/playback_control_bar.dart';
import 'components/status_capsule.dart';
import 'sections/synth_init_card.dart';
import 'utils/phase_helpers.dart';

class SynthesizePage extends StatefulWidget {
  const SynthesizePage({super.key, this.onNavigateToSettings});

  /// 提示"去设置"时回调(由 MainShell 切换到设置 Tab)。
  final VoidCallback? onNavigateToSettings;

  @override
  State<SynthesizePage> createState() => _SynthesizePageState();
}

class _SynthesizePageState extends State<SynthesizePage> {
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 进入合成页时预加载所选模型(已加载则忽略)。
    // 无模型时 prepareModel 内部自己会安全返回,不必额外判断。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<TtsStreamingService>().prepareModel();
    });
  }

  /// 下载目标模型,成功后启用它(卡片消失即是"启用成功"的反馈)。
  Future<void> _downloadAndEnable(
    ModelManager manager,
    TtsSettings settings,
    TtsModel target,
  ) async {
    await manager.downloadModel(target);
    if (manager.isDownloaded(target.id)) {
      await settings.selectModel(target.id);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _onSpeakPressed(TtsStreamingService service) async {
    final text = _textController.text;
    if (text.trim().isEmpty) {
      _showMessage(AppLocalizations.of(context).emptyTextError);
      return;
    }
    await service.speak(text);
    if (service.phase == StreamingPhase.error) {
      _showError(service.lastError);
      return;
    }
    _textController.clear();
    if (mounted) setState(() {});
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showError(String? error) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final msg = error ?? l10n.genericError;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        action: SnackBarAction(
          label: l10n.goSettings,
          onPressed: () => widget.onNavigateToSettings?.call(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<TtsStreamingService>();
    final settings = context.watch<TtsSettings>();
    final modelManager = context.watch<ModelManager>();
    final l10n = AppLocalizations.of(context);

    final selectedModel = ModelCatalog.byId(settings.selectedModelId);
    final modelReady =
        selectedModel != null && modelManager.isDownloaded(selectedModel.id);

    // 没有可用模型时,目标是"所选模型"(选了但没下载),否则推荐默认模型。
    final target = selectedModel ??
        ModelCatalog.byId(kDefaultSynthModelId) ??
        ModelCatalog.all.first;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.synthesizeTab),
        actions: [
          StatusCapsule(
            ready: modelReady,
            modelName: selectedModel?.displayName,
          ),
        ],
      ),
      body: SafeArea(
        child: modelReady
            ? Column(
                children: [
                  Expanded(
                    child: SpeakingBubblesView(
                      utterances: service.utterances,
                      activeIndex: service.activeIndex,
                      currentWordIndex: service.currentWordIndex,
                      autoScroll: settings.autoScroll,
                      onReplay: (i) => service.replayUtterance(i),
                    ),
                  ),
                  PlaybackControlBar(
                    service: service,
                    onTogglePlayPause: () async {
                      if (service.phase == StreamingPhase.paused) {
                        await service.resume();
                      } else if (service.phase == StreamingPhase.playing ||
                          service.phase == StreamingPhase.synthesizing) {
                        await service.pause();
                      }
                    },
                    onStop: () => service.stop(),
                  ),
                  InputBar(
                    controller: _textController,
                    onChange: () => setState(() {}),
                    isEmpty: _textController.text.isEmpty,
                    active: isActiveStreamingPhase(service.phase),
                    loading: service.modelLoading,
                    onSend: () => _onSpeakPressed(service),
                    onStop: () => service.stop(),
                  ),
                ],
              )
            : SynthInitCard(
                target: target,
                selected: selectedModel != null,
                state: modelManager.stateOf(target),
                onDownload: () =>
                    _downloadAndEnable(modelManager, settings, target),
                onCancel: () => modelManager.cancelDownload(target),
                onOpenSettings: () => widget.onNavigateToSettings?.call(),
              ),
      ),
    );
  }
}
