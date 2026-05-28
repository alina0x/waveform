import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/colors.dart';

/// Рендер `AsyncValue`: единый стиль загрузки и ошибки (retry).
/// На загрузку — `skeleton` (рекомендуется, рисует layout-плейсхолдер сразу)
/// или дефолтный acid-spinner если skeleton не задан.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.value,
    required this.data,
    this.skeleton,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;

  /// Кастомный плейсхолдер на loading. Перебивает дефолтный спиннер.
  final WidgetBuilder? skeleton;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: data,
      loading: () => skeleton != null
          ? skeleton!(context)
          : const Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.acid,
                ),
              ),
            ),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 28, color: AppColors.textLow),
            const SizedBox(height: 12),
            const Text("couldn't load",
                style: TextStyle(fontSize: 14, color: AppColors.textMid)),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text('$e',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppTheme.mono(size: 10, color: AppColors.textLow)),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              _RetryButton(onTap: onRetry!),
            ],
          ],
        ),
      ),
    );
  }
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: AppTheme.borderRadius,
            border: AppTheme.border(),
          ),
          child: Text('retry',
              style: AppTheme.mono(size: 12, color: AppColors.textHi)),
        ),
      ),
    );
  }
}
