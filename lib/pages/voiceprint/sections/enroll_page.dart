/// 注册说话人整页:声纹模型 + 名字 + 备注 + 圆形录音按钮 + 保存(支持连续注册多个)。
///
/// 声纹模型可选:不同模型的档案互相独立,这里选中的即"要写进哪个桶",
/// 同时会写回设置 —— 也就是"记住上次选择"。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter_tts_demo/components/theme/app_colors.dart';
import 'package:flutter_tts_demo/components/theme/app_text.dart';
import 'package:flutter_tts_demo/data/models/tts_settings.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';
import 'package:flutter_tts_demo/utils/voiceprint_service.dart';

import '../components/record_button.dart';
import '../utils/record_samples.dart';
import '../utils/voiceprint_auth.dart';

class EnrollSpeakerPage extends StatefulWidget {
  const EnrollSpeakerPage({super.key});

  @override
  State<EnrollSpeakerPage> createState() => _EnrollSpeakerPageState();
}

class _EnrollSpeakerPageState extends State<EnrollSpeakerPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final List<Float32List> _segments = [];
  bool _recording = false;
  int _enrolledCount = 0;

  /// 本次要写入的声纹模型(初值 = 设置里记住的上次选择)。
  String? _modelId;

  @override
  void initState() {
    super.initState();
    _modelId = context.read<VoiceprintService>().currentModelId;
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _recordOne() async {
    final samples = await recordSamples(context, (r) {
      if (mounted) setState(() => _recording = r);
    });
    if (mounted) setState(() => _segments.add(samples));
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _segments.isEmpty) return;
    // 录入是信任根:谁能录入谁就能通过识别,所以写库前先过设备认证。
    if (!await ensureVoiceprintAuth(context)) return;
    if (!mounted) return;
    try {
      await context.read<VoiceprintService>().enroll(
            name: name,
            note: _note.text.trim(),
            samples: _segments,
            modelId: _modelId,
          );
      if (!mounted) return;
      // 清空表单,支持连续注册多个说话人。
      setState(() {
        _name.clear();
        _note.clear();
        _segments.clear();
        _enrolledCount++;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已注册「$name」')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final service = context.watch<VoiceprintService>();
    final models = service.downloadedSpeakerModels;
    final canSave = _name.text.trim().isNotEmpty &&
        _segments.isNotEmpty &&
        _modelId != null;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.enrollSpeaker)),
      // 内容带 Spacer,又必须在键盘弹出时能滚:用
      // SingleChildScrollView + minHeight 约束 + IntrinsicHeight 让
      // Spacer 在空间够时仍然撑开、不够时整体可滚。
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _name,
                      decoration: InputDecoration(
                        labelText: l10n.enrollName,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _note,
                      decoration: InputDecoration(
                        labelText: l10n.enrollNote,
                        hintText: l10n.speakerNoteHint,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (models.isEmpty)
                      Text(
                        l10n.noModelDownloaded,
                        style: AppText.caption.copyWith(color: AppColors.danger),
                      )
                    else ...[
                      DropdownButtonFormField<String>(
                        key: const ValueKey('enrollVoiceprintModelSelector'),
                        initialValue: _modelId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: l10n.voiceprintModelLabel,
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          for (final m in models)
                            DropdownMenuItem(
                              value: m.id,
                              child: Text(
                                m.displayName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (id) {
                          if (id == null) return;
                          setState(() => _modelId = id);
                          // 写回设置 = 记住上次选择。
                          unawaited(
                            context.read<TtsSettings>().setVoiceprintModelId(id),
                          );
                        },
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.voiceprintModelIsolationHint,
                        style: AppText.caption,
                      ),
                    ],
                    const Spacer(),
                    RecordButton(recording: _recording, onTap: _recordOne),
                    const SizedBox(height: 16),
                    Text(
                      _recording
                          ? l10n.recording
                          : '${l10n.enrollSegmentsHint}(已录 ${_segments.length} 段)',
                      style: AppText.caption,
                      textAlign: TextAlign.center,
                    ),
                    if (_enrolledCount > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '本次已注册 $_enrolledCount 位',
                        style: AppText.caption.copyWith(color: AppColors.success),
                      ),
                    ],
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const ValueKey('saveSpeakerButton'),
                        onPressed: canSave ? _save : null,
                        child: Text(l10n.save),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
