import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/colors.dart';
import '../../core/api/feeds.dart';
import '../../core/api/soundcloud_auth.dart';
import '../../core/cache/image_cache.dart';
import '../../shared/widgets/frosted.dart';
import '../../shared/widgets/pressable.dart';
import '../player/player_controller.dart';
import 'omnibox_providers.dart';
import 'recent_queries.dart';

/// Дроп-даун омнибокса: actions / jump-to / live search / recent queries.
/// Видим, когда поле в фокусе. Закрывается потерей фокуса (Esc / клик мимо
/// через невидимый scrim в AppShell). Один путь ввода — поиск + командная
/// палитра в том же поле.
class OmniboxDropdown extends ConsumerWidget {
  const OmniboxDropdown({super.key});

  /// Закрыть: убрать фокус с поля.
  void _close(WidgetRef ref) =>
      ref.read(omniboxFocusProvider).unfocus();

  void _navigate(BuildContext context, WidgetRef ref, String location,
      {bool push = false}) {
    _close(ref);
    if (push) {
      context.push(location);
    } else {
      context.go(location);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(omniboxQueryProvider);
    final recents = ref.watch(recentQueriesProvider);
    final actions = _matchedActions(q);

    final sections = <Widget>[];

    if (q.isEmpty) {
      if (recents.isNotEmpty) {
        sections.add(_Section(
          title: 'recent',
          children: [
            for (final r in recents)
              _Row(
                icon: Icons.history,
                title: r,
                onTap: () {
                  ref.read(omniboxControllerProvider).text = r;
                  ref.read(omniboxQueryProvider.notifier).set(r);
                  _navigate(context, ref, '/search?q=${Uri.encodeQueryComponent(r)}');
                },
              ),
          ],
        ));
      } else {
        sections.add(const _EmptyHint(
            text: 'type to search — or use commands like “settings” / “logs”'));
      }
    } else {
      if (actions.isNotEmpty) {
        sections.add(_Section(
          title: 'actions',
          children: [
            for (final a in actions)
              _Row(
                icon: a.icon,
                title: a.label,
                onTap: () {
                  a.run(context, ref);
                  _close(ref);
                },
              ),
          ],
        ));
      }

      final results = ref.watch(searchProvider(q));
      results.when(
        loading: () => null,
        error: (_, _) => null,
        data: (r) {
          final picks = <Widget>[];
          for (final t in r.tracks.take(3)) {
            picks.add(_Row(
              icon: Icons.music_note,
              title: t.title,
              subtitle: t.artist,
              onTap: () => _navigate(context, ref, '/track/${t.id}'),
            ));
          }
          for (final p in r.playlists.take(2)) {
            picks.add(_Row(
              icon: Icons.library_music_outlined,
              title: p.title,
              subtitle: p.subtitle,
              onTap: () => _navigate(context, ref, '/playlist/${p.id}'),
            ));
          }
          for (final a in r.artists.take(2)) {
            picks.add(_Row(
              icon: Icons.person_outline,
              title: a.name,
              subtitle: '@${a.handle}',
              onTap: () => _navigate(context, ref,
                  '/artist/${Uri.encodeComponent(a.handle)}'),
            ));
          }
          if (picks.isNotEmpty) {
            sections.add(_Section(title: 'from soundcloud', children: picks));
          }
        },
      );

      // Финальная подсказка — Enter / клик ведёт на /search.
      sections.add(_Row(
        icon: Icons.search,
        title: 'search "$q" →',
        accent: true,
        onTap: () {
          ref.read(recentQueriesProvider.notifier).add(q);
          _navigate(context, ref, '/search?q=${Uri.encodeQueryComponent(q)}');
        },
      ));
    }

    return FrostedBar(
      sigma: 14,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 480),
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.92),
          borderRadius: AppTheme.borderRadius,
          border: AppTheme.border(),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: sections,
          ),
        ),
      ),
    );
  }

  /// Сматчить query на доступные действия. Простой substring + alias-набор.
  List<_OmniboxAction> _matchedActions(String q) {
    final ql = q.toLowerCase();
    bool m(List<String> aliases) => aliases.any((a) => a.contains(ql));
    return [
      if (m(const ['settings', 'set', 'prefs', 'options', 'config']))
        _OmniboxAction(
          icon: Icons.settings_outlined,
          label: 'open settings',
          run: (c, _) => c.push('/settings'),
        ),
      if (m(const ['logs', 'log', 'talker', 'debug']))
        _OmniboxAction(
          icon: Icons.terminal,
          label: 'open logs',
          run: (c, _) => c.push('/logs'),
        ),
      if (m(const ['likes', 'like', 'favorites', 'heart']))
        _OmniboxAction(
          icon: Icons.favorite_outline,
          label: 'go to library / likes',
          run: (c, _) => c.go('/library?tab=likes'),
        ),
      if (m(const ['shuffle']))
        _OmniboxAction(
          icon: Icons.shuffle,
          label: 'toggle shuffle',
          run: (_, ref) =>
              ref.read(playerControllerProvider.notifier).toggleShuffle(),
        ),
      if (m(const ['sign out', 'signout', 'logout', 'log out']))
        _OmniboxAction(
          icon: Icons.logout,
          label: 'sign out of soundcloud',
          run: (_, ref) =>
              ref.read(authControllerProvider.notifier).signOut(),
        ),
      if (m(const ['cache', 'clear cache', 'reset cache', 'covers']))
        _OmniboxAction(
          icon: Icons.cleaning_services_outlined,
          label: 'clear cover art cache',
          run: (_, _) => waveformImageCache.emptyCache(),
        ),
    ];
  }
}

class _OmniboxAction {
  _OmniboxAction({required this.icon, required this.label, required this.run});
  final IconData icon;
  final String label;
  final void Function(BuildContext context, WidgetRef ref) run;
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: Text(title.toUpperCase(),
              style: AppTheme.mono(
                  size: 9,
                  color: AppColors.textLow,
                  weight: FontWeight.w600,
                  letterSpacing: 1.4)),
        ),
        ...children,
        const SizedBox(height: 4),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    this.subtitle,
    this.accent = false,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool accent;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      hoverFill: false, // у нас своя hover-логика через окраску текста.
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(icon,
                size: 15,
                color: accent ? AppColors.acid : AppColors.textMid),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: accent ? AppColors.acid : AppColors.textHi)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.mono(
                            size: 10, color: AppColors.textMid)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      child: Text(text,
          style: AppTheme.mono(size: 11, color: AppColors.textMid)),
    );
  }
}
