/// 顶部状态胶囊:模型就绪状态 + 名称。
library;

import 'package:flutter/material.dart';

import 'package:flutter_tts_demo/components/theme/app_colors.dart';
import 'package:flutter_tts_demo/components/theme/app_spacing.dart';
import 'package:flutter_tts_demo/components/theme/app_text.dart';
import 'package:flutter_tts_demo/l10n/app_localizations.dart';

class StatusCapsule extends StatelessWidget {
  const StatusCapsule({super.key, required this.ready, this.modelName});

  final bool ready;
  final String? modelName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = ready ? AppColors.success : AppColors.warn;
    final text = ready
        ? (modelName ?? l10n.statusReady)
        : (modelName == null ? l10n.statusNoModel : l10n.statusNotDownloaded);
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Chip(
        avatar: Icon(
          ready ? Icons.check_circle_outline : Icons.warning_amber_outlined,
          size: 16,
          color: color,
        ),
        label: Text(
          text,
          style: AppText.caption.copyWith(color: color),
          overflow: TextOverflow.ellipsis,
        ),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
