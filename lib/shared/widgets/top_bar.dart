import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/colors.dart';
import '../../core/api/feeds.dart';
import '../../core/api/soundcloud_auth.dart';
import '../../features/auth/login_dialog.dart';
import '../../features/omnibox/omnibox_providers.dart';
import '../../features/omnibox/recent_queries.dart';
import '../../features/player/player_controller.dart';
import '../../features/queue/queue_visibility.dart';
import 'cover_art.dart';
import 'pressable.dart';
import 'wave_logo.dart';

/// Верхняя панель оболочки: лого, навигация Home/Feed/Library, поиск,
/// аккаунт (логин/логаут). Активный пункт — по маршруту.
class TopBar extends ConsumerWidget {
  const TopBar({
    super.key,
    required this.location,
  });

  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // На macOS оставляем место слева под «светофор» окна.
    final leftPad = Platform.isMacOS ? 80.0 : 16.0;
    return Container(
      height: AppTheme.topBarHeight,
      padding: EdgeInsets.only(left: leftPad, right: 16),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.72),
        border: const Border(bottom: AppTheme.borderSideStatic),
      ),
      child: Row(
        children: [
          const WaveLogo(),
          const SizedBox(width: 10),
          Text(
            'waveform',
            style: AppTheme.mono(
              size: 15,
              color: AppColors.textHi,
              weight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 32),
          _NavLink('home', '/', location),
          _NavLink('feed', '/feed', location),
          _NavLink('library', '/library', location),
          const SizedBox(width: 16),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: const _SearchField(),
              ),
            ),
          ),
          const SizedBox(width: 16),
          if (kDebugMode) ...[
            Pressable(
              onTap: () => context.push('/logs'),
              child: Tooltip(
                message: 'logs',
                child: Icon(Icons.terminal,
                    size: 16, color: AppColors.textLow),
              ),
            ),
            const SizedBox(width: 14),
          ],
          Consumer(builder: (context, ref, _) {
            final on = ref.watch(queueVisibleProvider);
            return Pressable(
              onTap: () => ref.read(queueVisibleProvider.notifier).toggle(),
              child: Tooltip(
                message: 'queue',
                child: Icon(Icons.queue_music,
                    size: 16,
                    color: on ? AppColors.acid : AppColors.textLow),
              ),
            );
          }),
          const SizedBox(width: 14),
          Pressable(
            onTap: () => context.push('/settings'),
            child: const Tooltip(
              message: 'settings',
              child: Icon(Icons.settings_outlined,
                  size: 16, color: AppColors.textLow),
            ),
          ),
          const SizedBox(width: 14),
          const _Account(),
        ],
      ),
    );
  }
}

/// Аккаунт: разлогинен → кнопка «log in»; залогинен → аватар с меню (logout).
class _Account extends ConsumerWidget {
  const _Account();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authed = ref.watch(authControllerProvider).isAuthenticated;

    if (!authed) {
      return Pressable(
        onTap: () => showLoginDialog(context),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.acid,
            borderRadius: AppTheme.borderRadius,
          ),
          child: Text('log in',
              style: AppTheme.mono(
                  size: 12, color: AppColors.bg, weight: FontWeight.w600)),
        ),
      );
    }

    // Реальная аватарка из профиля (/me через rail); до загрузки — процедурная.
    final me = ref.watch(railProvider).asData?.value.me;
    return PopupMenuButton<String>(
      tooltip: 'account',
      color: AppColors.surface2,
      shape: const RoundedRectangleBorder(borderRadius: AppTheme.borderRadius),
      onSelected: (v) {
        if (v == 'logout') ref.read(authControllerProvider.notifier).signOut();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'logout',
          child: Text('log out',
              style: AppTheme.mono(size: 12, color: AppColors.textHi)),
        ),
      ],
      child: CoverArt(
          seed: 'me', imageUrl: me?.avatarUrl, size: 30, circular: true),
    );
  }
}

class _NavLink extends StatelessWidget {
  const _NavLink(this.label, this.path, this.location);

  final String label;
  final String path;
  final String location;

  bool get _active =>
      path == '/' ? location == '/' : location.startsWith(path);

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.go(path),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: _active ? FontWeight.w600 : FontWeight.w400,
              color: _active ? AppColors.textHi : AppColors.textMid,
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    // Дебаунсим обновление query-провайдера — дроп-даун (Phase 2b) и любые
    // живые подписки на `omniboxQueryProvider` обновятся через 250ms.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      ref.read(omniboxQueryProvider.notifier).set(value.trim());
    });
  }

  void _submit(String value) {
    final q = value.trim();
    if (q.isEmpty) return;
    ref.read(recentQueriesProvider.notifier).add(q);
    ref.read(omniboxFocusProvider).unfocus();
    context.go('/search?q=${Uri.encodeQueryComponent(q)}');
  }

  @override
  Widget build(BuildContext context) {
    final focus = ref.watch(omniboxFocusProvider);
    final controller = ref.watch(omniboxControllerProvider);
    // Когда поле пустое и трек играет — placeholder показывает now-playing,
    // закрывая потребность в отдельном ticker'е в TopBar.
    final track = ref.watch(playerControllerProvider).track;
    final hint = (controller.text.isEmpty && track != null)
        ? '⌘K · playing: ${track.artist} — ${track.title}'
        : '⌘K · search tracks, artists, playlists…';

    return Container(
      width: double.infinity,
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: AppTheme.borderRadius,
        border: AppTheme.border(),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 15, color: AppColors.textLow),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              onChanged: _onChanged,
              onSubmitted: _submit,
              textInputAction: TextInputAction.search,
              cursorColor: AppColors.acid,
              style: const TextStyle(fontSize: 12, color: AppColors.textHi),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle:
                    const TextStyle(fontSize: 12, color: AppColors.textLow),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

