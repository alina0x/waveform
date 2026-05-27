import 'package:flutter/material.dart';

import '../app/theme/app_theme.dart';
import '../app/theme/colors.dart';
import '../core/api/soundcloud_api.dart';
import '../core/api/webview_login.dart';

/// Реакция UI на исход лайка. Тихо при [LikeOutcome.ok]; при `blocked` —
/// предложение пройти верификацию в браузере (капча/анти-абуз, частый под VPN);
/// при `failed` — короткое уведомление.
void showLikeOutcome(BuildContext context, LikeOutcome outcome) {
  if (outcome == LikeOutcome.ok) return;
  final messenger = ScaffoldMessenger.of(context);
  final blocked = outcome == LikeOutcome.blocked;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surface2,
      duration: Duration(seconds: blocked ? 6 : 3),
      content: Text(
        blocked
            ? 'SoundCloud blocked this action — likely a captcha/VPN check'
            : "couldn't update like",
        style: AppTheme.mono(size: 12, color: AppColors.textHi),
      ),
      action: blocked
          ? SnackBarAction(
              label: 'verify',
              textColor: AppColors.acid,
              onPressed: () => WebviewLogin.openVerification(),
            )
          : null,
    ));
}

/// Уведомление, что трек доступен только по подписке GO+ и не проигрывается.
void showGoPlusNotice(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surface2,
      duration: const Duration(seconds: 3),
      content: Text(
        'GO+ only — needs a SoundCloud GO+ subscription to play',
        style: AppTheme.mono(size: 12, color: AppColors.textHi),
      ),
    ));
}
