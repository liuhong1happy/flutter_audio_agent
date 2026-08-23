/// 底部输入栏(需求:输入框在最底部)。
library;

import 'package:flutter/material.dart';

import 'package:flutter_tts_demo/components/theme/app_colors.dart';
import 'package:flutter_tts_demo/components/theme/app_spacing.dart';
import 'package:flutter_tts_demo/components/theme/app_text.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';

class InputBar extends StatelessWidget {
  const InputBar({
    super.key,
    required this.controller,
    required this.onChange,
    required this.isEmpty,
    required this.active,
    required this.loading,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final VoidCallback onChange;
  final bool isEmpty;
  final bool active;

  /// 模型预加载中(发送按钮禁用)。
  final bool loading;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('ttsInput'),
                  controller: controller,
                  maxLines: 3,
                  minLines: 1,
                  onChanged: (_) => onChange(),
                  style: AppText.body,
                  decoration: InputDecoration(
                    hintText: l10n.inputHint,
                    isDense: true,
                    suffixIcon: isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              controller.clear();
                              onChange();
                            },
                          ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton.icon(
                key: const ValueKey('speakButton'),
                onPressed: active ? onStop : (loading ? null : onSend),
                icon: Icon(
                  active
                      ? Icons.stop
                      : (loading ? Icons.hourglass_empty : Icons.send),
                ),
                label: Text(
                  active
                      ? l10n.stop
                      : (loading ? l10n.loadingModel : l10n.send),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
