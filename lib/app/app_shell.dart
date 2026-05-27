import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/player/player_controller.dart';
import '../features/player/widgets/bottom_player.dart';
import '../shared/widgets/frosted.dart';
import '../shared/widgets/top_bar.dart';
import 'theme/app_theme.dart';
import 'theme/colors.dart';

/// Оболочка приложения: контент на всю высоту, поверх — фрост-TopBar и
/// фрост-BottomPlayer (контент скроллится под ними сквозь блюр).
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Уведомление, когда трек не проиграть (GO+/недоступен) — чтобы не «молча».
    ref.listen(playerControllerProvider.select((s) => s.unplayable),
        (prev, next) {
      if (next == null || next.seq == prev?.seq) return;
      final msg = next.goPlus
          ? '“${next.title}” is GO+ only — can’t play without a subscription'
          : '“${next.title}” is unavailable — skipped';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surface2,
          duration: const Duration(seconds: 3),
          content: Text(msg,
              style: AppTheme.mono(size: 12, color: AppColors.textHi)),
        ));
    });
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Positioned.fill(child: child),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FrostedBar(
              child: TopBar(location: location),
            ),
          ),
          const Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: FrostedBar(child: BottomPlayer()),
          ),
        ],
      ),
    );
  }
}

/// Отступы контента под фрост-хрому — добавляются к скроллу каждого экрана.
const double kContentTop = AppTheme.topBarHeight;
const double kContentBottom = AppTheme.playerHeight;
