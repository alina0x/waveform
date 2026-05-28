import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/omnibox/omnibox_dropdown.dart';
import '../features/omnibox/omnibox_providers.dart';
import '../features/player/player_controller.dart';
import '../features/player/widgets/bottom_player.dart';
import '../core/lastfm/scrobbler.dart';
import '../features/queue/queue_panel.dart';
import '../features/queue/queue_visibility.dart';
import '../shared/intents.dart';
import '../shared/widgets/frosted.dart';
import '../shared/widgets/top_bar.dart';
import 'theme/app_theme.dart';
import 'theme/colors.dart';

/// Оболочка приложения: контент на всю высоту, поверх — фрост-TopBar и
/// фрост-BottomPlayer (контент скроллится под ними сквозь блюр). Здесь же
/// глобальные клавиатурные шорткаты (Shortcuts + Actions): play/pause,
/// next/prev, ⌘K/⌘F фокус в омнибокс, jump-ы в likes/settings/logs.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Lazy-bootstrap скробблера: provider создаст Notifier, который подпишется
    // на playerController. Значение не используется, важен side-effect.
    ref.watch(lastfmScrobblerProvider);

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

    final player = ref.read(playerControllerProvider.notifier);
    final omniboxFocus = ref.read(omniboxFocusProvider);
    final omniboxCtrl = ref.read(omniboxControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Shortcuts(
        shortcuts: _shortcuts(),
        child: Actions(
          actions: <Type, Action<Intent>>{
            PlayPauseIntent: CallbackAction<PlayPauseIntent>(
              onInvoke: (_) {
                player.toggle();
                return null;
              },
            ),
            NextTrackIntent: CallbackAction<NextTrackIntent>(
              onInvoke: (_) {
                player.next();
                return null;
              },
            ),
            PrevTrackIntent: CallbackAction<PrevTrackIntent>(
              onInvoke: (_) {
                player.previous();
                return null;
              },
            ),
            FocusOmniboxIntent: CallbackAction<FocusOmniboxIntent>(
              onInvoke: (_) {
                omniboxFocus.requestFocus();
                // Выделяем весь текст — пользователь сразу пишет поверх.
                omniboxCtrl.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: omniboxCtrl.text.length,
                );
                return null;
              },
            ),
            JumpLikesIntent: CallbackAction<JumpLikesIntent>(
              onInvoke: (_) {
                context.go('/library?tab=likes');
                return null;
              },
            ),
            JumpSettingsIntent: CallbackAction<JumpSettingsIntent>(
              onInvoke: (_) {
                context.push('/settings');
                return null;
              },
            ),
            JumpLogsIntent: CallbackAction<JumpLogsIntent>(
              onInvoke: (_) {
                context.push('/logs');
                return null;
              },
            ),
          },
          // autofocus=true → root-фокус берёт unhandled-keys; TextField, когда
          // фокус в нём, перехватывает Space/стрелки до подъёма к Shortcuts.
          child: Focus(
            autofocus: true,
            child: Consumer(builder: (context, ref, _) {
              final omniOpen = ref.watch(omniboxFocusedProvider);
              final queueOpen = ref.watch(queueVisibleProvider);
              return Stack(
                children: [
                  Positioned.fill(child: child),
                  // Queue-панель справа, под TopBar и над BottomPlayer.
                  if (queueOpen)
                    const Positioned(
                      top: AppTheme.topBarHeight,
                      bottom: AppTheme.playerHeight,
                      right: 0,
                      width: 320,
                      child: QueuePanel(),
                    ),
                  // Невидимый scrim над контентом, чтобы клик мимо дроп-дауна
                  // снимал фокус. Под TopBar / над BottomPlayer, не мешает им.
                  if (omniOpen)
                    Positioned(
                      top: AppTheme.topBarHeight,
                      left: 0,
                      right: queueOpen ? 320 : 0,
                      bottom: AppTheme.playerHeight,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () =>
                            ref.read(omniboxFocusProvider).unfocus(),
                      ),
                    ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: FrostedBar(
                      child: TopBar(location: location),
                    ),
                  ),
                  // Дроп-даун омнибокса — якорится под TopBar справа, ширина
                  // ~360, чтобы вмещать иконку + заголовок + сабсаб.
                  if (omniOpen)
                    Positioned(
                      top: AppTheme.topBarHeight + 4,
                      right: queueOpen ? 320 + 16 : 16,
                      width: 360,
                      child: const OmniboxDropdown(),
                    ),
                  const Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: FrostedBar(child: BottomPlayer()),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  /// Кросс-платформенные шорткаты: на macOS — Cmd, на остальных — Ctrl.
  /// Space / ← / → без модификаторов — TextField их сам перехватит когда в фокусе.
  Map<ShortcutActivator, Intent> _shortcuts() {
    final mac = Platform.isMacOS;
    SingleActivator cmd(LogicalKeyboardKey key, {bool shift = false}) =>
        SingleActivator(key, meta: mac, control: !mac, shift: shift);
    return <ShortcutActivator, Intent>{
      const SingleActivator(LogicalKeyboardKey.space): const PlayPauseIntent(),
      const SingleActivator(LogicalKeyboardKey.arrowLeft): const PrevTrackIntent(),
      const SingleActivator(LogicalKeyboardKey.arrowRight): const NextTrackIntent(),
      cmd(LogicalKeyboardKey.keyK): const FocusOmniboxIntent(),
      cmd(LogicalKeyboardKey.keyF): const FocusOmniboxIntent(),
      cmd(LogicalKeyboardKey.keyL): const JumpLikesIntent(),
      cmd(LogicalKeyboardKey.comma): const JumpSettingsIntent(),
      cmd(LogicalKeyboardKey.keyL, shift: true): const JumpLogsIntent(),
    };
  }
}

/// Отступы контента под фрост-хрому — добавляются к скроллу каждого экрана.
const double kContentTop = AppTheme.topBarHeight;
const double kContentBottom = AppTheme.playerHeight;
