import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/colors.dart';
import '../../features/auth/login_dialog.dart';
import 'pressable.dart';

/// Заглушка для персональных экранов в разлогиненном состоянии:
/// объяснение + кнопка входа. Не фейкаем личный контент анонимам.
class LoggedOutView extends StatelessWidget {
  const LoggedOutView({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.playerHeight),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 30, color: AppColors.textLow),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHi)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(subtitle,
                  textAlign: TextAlign.center,
                  style: AppTheme.mono(size: 12, color: AppColors.textMid)),
            ),
            const SizedBox(height: 20),
            Pressable(
              onTap: () => showLoginDialog(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                decoration: BoxDecoration(
                  color: AppColors.acid,
                  borderRadius: AppTheme.borderRadius,
                ),
                child: Text('log in',
                    style: AppTheme.mono(
                        size: 12, color: AppColors.bg, weight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
