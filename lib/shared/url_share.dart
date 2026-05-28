import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme/app_theme.dart';
import '../app/theme/colors.dart';

/// Открывает URL в системном браузере без `url_launcher` (нативные shell-команды
/// на каждой ОС). Best-effort — тихо проглатывает ошибки.
Future<void> openExternalUrl(String url) async {
  try {
    if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', url]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [url]);
    }
  } catch (_) {/* ignore — пользователь увидит тихий no-op */}
}

/// Копирует строку в системный clipboard и показывает короткий toast.
/// Если [context] больше не mounted — silent.
Future<void> copyToClipboard(BuildContext context, String text,
    {String message = 'link copied to clipboard'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surface2,
      content: Text(message,
          style: AppTheme.mono(size: 12, color: AppColors.textHi)),
    ));
}
