import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import '../core/lastfm/scrobbler.dart';
import '../core/log/talker.dart';
import '../features/omnibox/omnibox_dropdown.dart';
import '../features/omnibox/omnibox_providers.dart';
import '../features/player/player_controller.dart';
import '../features/player/widgets/bottom_player.dart';
import '../features/queue/queue_panel.dart';
import '../features/queue/queue_visibility.dart';
import '../shared/intents.dart';
import '../shared/models/track.dart';
import '../shared/widgets/frosted.dart';
import '../shared/widgets/top_bar.dart';
import 'theme/app_theme.dart';
import 'theme/colors.dart';

/// Оболочка приложения. Поверх контента — фрост-TopBar и фрост-BottomPlayer.
/// Здесь же глобальные клавиатурные шорткаты (Shortcuts + Actions),
/// центральная ⌘K-палитра поверх blur-фона, queue-панель справа.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Lazy-bootstrap скробблера: provider создаст Notifier, который подпишется
    // на playerController.
    ref.watch(lastfmScrobblerProvider);

    // Динамический title окна — отражает текущий трек на desktop.
    ref.listen<Track?>(playerControllerProvider.select((s) => s.track),
        (prev, next) async {
      if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
        return;
      }
      final title = next == null
          ? 'Waveform'
          : 'Waveform · ${next.artist} — ${next.title}';
      try {
        await windowManager.setTitle(title);
      } catch (e, st) {
        // Логируем, чтобы видно было если плагин не настроен.
        ref.read(talkerProvider).warning('setTitle failed', e, st);
      }
    });

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

    return Scaffold(
      backgroundColor: AppColors.bg,
      // Внешний Focus глотает все unhandled-ключи без System-beep'а на macOS
      // (когда нет фокуса на TextField и Shortcuts не совпали).
      body: Focus(
        canRequestFocus: false,
        onKeyEvent: (_, _) => KeyEventResult.handled,
        child: Shortcuts(
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
              VolumeUpIntent: CallbackAction<VolumeUpIntent>(
                onInvoke: (_) {
                  final cur = ref.read(playerControllerProvider).volume;
                  player.setVolume((cur + 0.05).clamp(0.0, 1.0));
                  return null;
                },
              ),
              VolumeDownIntent: CallbackAction<VolumeDownIntent>(
                onInvoke: (_) {
                  final cur = ref.read(playerControllerProvider).volume;
                  player.setVolume((cur - 0.05).clamp(0.0, 1.0));
                  return null;
                },
              ),
              FocusOmniboxIntent: CallbackAction<FocusOmniboxIntent>(
                onInvoke: (_) {
                  ref.read(omniboxOpenProvider.notifier).open();
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
            child: Focus(
              autofocus: true,
              child: Consumer(builder: (context, ref, _) {
                final omniOpen = ref.watch(omniboxOpenProvider);
                final queueOpen = ref.watch(queueVisibleProvider);
                return Stack(
                  children: [
                    Positioned.fill(child: child),
                    // Queue-панель справа.
                    if (queueOpen)
                      const Positioned(
                        top: AppTheme.topBarHeight,
                        bottom: AppTheme.playerHeight,
                        right: 0,
                        width: 320,
                        child: QueuePanel(),
                      ),
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
                    // ⌘K-палитра: полноэкранный blur-фон + центрированная
                    // модалка. Клик мимо — закрывает. Поверх TopBar/BottomPlayer.
                    if (omniOpen)
                      Positioned.fill(
                        child: _OmniboxOverlay(),
                      ),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  /// Кросс-платформенные шорткаты: на macOS — Cmd, на остальных — Ctrl.
  /// Space / ← / → / ↑ / ↓ без модификаторов — TextField их сам перехватит
  /// когда в фокусе (стрелки для каретки, space для пробела и т.д.).
  Map<ShortcutActivator, Intent> _shortcuts() {
    final mac = Platform.isMacOS;
    SingleActivator cmd(LogicalKeyboardKey key, {bool shift = false}) =>
        SingleActivator(key, meta: mac, control: !mac, shift: shift);
    return <ShortcutActivator, Intent>{
      const SingleActivator(LogicalKeyboardKey.space): const PlayPauseIntent(),
      const SingleActivator(LogicalKeyboardKey.arrowLeft):
          const PrevTrackIntent(),
      const SingleActivator(LogicalKeyboardKey.arrowRight):
          const NextTrackIntent(),
      const SingleActivator(LogicalKeyboardKey.arrowUp):
          const VolumeUpIntent(),
      const SingleActivator(LogicalKeyboardKey.arrowDown):
          const VolumeDownIntent(),
      cmd(LogicalKeyboardKey.keyK): const FocusOmniboxIntent(),
      cmd(LogicalKeyboardKey.keyF): const FocusOmniboxIntent(),
      cmd(LogicalKeyboardKey.keyL): const JumpLikesIntent(),
      cmd(LogicalKeyboardKey.comma): const JumpSettingsIntent(),
      cmd(LogicalKeyboardKey.keyL, shift: true): const JumpLogsIntent(),
    };
  }
}

/// Полноэкранный overlay: blur-фон + dim scrim + центрированная палитра.
/// Клик мимо палитры — закрытие.
class _OmniboxOverlay extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void close() => ref.read(omniboxOpenProvider.notifier).close();
    return Stack(
      children: [
        // Backdrop blur + dim. GestureDetector ловит клик мимо → close.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: close,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                color: AppColors.bg.withValues(alpha: 0.45),
              ),
            ),
          ),
        ),
        // Центральная модалка. Останавливаем тап на ней (через AbsorbPointer
        // или GestureDetector с прозрачным behavior нельзя — нужен absorb).
        Positioned.fill(
          child: IgnorePointer(
            ignoring: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).size.height * 0.14,
                  left: 24,
                  right: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  // GestureDetector на модалке поглощает клик — иначе он
                  // прорывался бы к scrim'у и закрывал палитру.
                  child: GestureDetector(
                    onTap: () {},
                    behavior: HitTestBehavior.opaque,
                    child: const OmniboxDropdown(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Отступы контента под фрост-хрому — добавляются к скроллу каждого экрана.
const double kContentTop = AppTheme.topBarHeight;
const double kContentBottom = AppTheme.playerHeight;
