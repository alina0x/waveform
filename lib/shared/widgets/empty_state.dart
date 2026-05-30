import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/colors.dart';
import 'pressable.dart';

/// Унифицированный «пустой» state: икона + заголовок + сабсаб + optional CTA.
/// Используется везде, где раньше была серая полупустая зона: «no likes yet»,
/// «no results for …», «nothing in your stream» и т.д. По стилю — спокойный
/// minimal, без acid (acid только если есть CTA).
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Сжатый вариант (для секций внутри списка — без большого вертикального
  /// центрирования).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: compact ? 24 : 30, color: AppColors.textLow),
        SizedBox(height: compact ? 10 : 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: compact ? 14 : 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textHi,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: AppTheme.mono(size: 12, color: AppColors.textMid),
            ),
          ),
        ],
        if (onAction != null && actionLabel != null) ...[
          const SizedBox(height: 18),
          Pressable(
            onTap: onAction!,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.acid,
                borderRadius: AppTheme.borderRadius,
              ),
              child: Text(
                actionLabel!,
                style: AppTheme.mono(
                  size: 12,
                  color: AppColors.bg,
                  weight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ],
    );
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(child: body),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.playerHeight),
      child: Center(child: body),
    );
  }
}
