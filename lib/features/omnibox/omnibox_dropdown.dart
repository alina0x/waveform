import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/colors.dart';
import '../../core/api/feeds.dart';
import '../../core/api/soundcloud_auth.dart';
import '../../core/cache/image_cache.dart';
import '../player/player_controller.dart';
import 'omnibox_providers.dart';
import 'recent_queries.dart';

/// Центральная ⌘K-палитра: большой acid-обведённый input, заголовок сверху,
/// результаты ниже. Рендерится в AppShell как overlay поверх blur-фона.
///
/// Apple/Raycast-like: scale+fade entrance (~200ms ease-out), Esc закрывает,
/// клик мимо закрывает (через scrim в AppShell). Контроллер запроса
/// переживает закрытие — повторный ⌘K возвращает к тому же тексту.
class OmniboxDropdown extends ConsumerStatefulWidget {
  const OmniboxDropdown({super.key});

  @override
  ConsumerState<OmniboxDropdown> createState() => _OmniboxDropdownState();
}

class _OmniboxDropdownState extends ConsumerState<OmniboxDropdown>
    with SingleTickerProviderStateMixin {
  Timer? _debounce;
  late final AnimationController _entry = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 200))
    ..forward();

  @override
  void initState() {
    super.initState();
    // После маунта — выделить весь существующий текст. Фокус ставит
    // FocusScope.autofocus у TextField, нам ничего вручную просить не надо
    // (раньше competing autofocus в AppShell блокировал ввод).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctrl = ref.read(omniboxControllerProvider);
      ctrl.selection =
          TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _entry.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      ref.read(omniboxQueryProvider.notifier).set(v.trim());
    });
  }

  void _close() => ref.read(omniboxOpenProvider.notifier).close();

  void _navigate(String location, {bool push = false}) {
    _close();
    if (push) {
      context.push(location);
    } else {
      context.go(location);
    }
  }

  void _submit(String value) {
    final q = value.trim();
    if (q.isEmpty) return;
    ref.read(recentQueriesProvider.notifier).add(q);
    _navigate('/search?q=${Uri.encodeQueryComponent(q)}');
  }

  /// Esc → закрыть. Возвращает handled, чтобы не уходило в outer-onKeyEvent.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(omniboxControllerProvider);
    final focus = ref.watch(omniboxFocusProvider);
    final query = ref.watch(omniboxQueryProvider);
    final recents = ref.watch(recentQueriesProvider);
    final actions = _matchedActions(query);
    final track = ref.watch(playerControllerProvider).track;

    final placeholder = (controller.text.isEmpty && track != null)
        ? 'playing: ${track.artist} — ${track.title}'
        : 'search tracks, artists, playlists, or run a command…';

    // Анимация входа: scale + fade.
    final scale = Tween<double>(begin: 0.96, end: 1.0).animate(
        CurvedAnimation(parent: _entry, curve: Curves.easeOutCubic));
    final opacity = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _entry, curve: Curves.easeOutCubic));

    return FocusScope(
      autofocus: true,
      onKeyEvent: _onKey,
      child: FadeTransition(
        opacity: opacity,
        child: ScaleTransition(
          scale: scale,
          alignment: Alignment.topCenter,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.94),
              borderRadius: AppTheme.borderRadius,
              border: AppTheme.border(),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 40,
                  offset: const Offset(0, 24),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('⌘K · SEARCH WAVEFORM',
                              style: AppTheme.mono(
                                  size: 10,
                                  color: AppColors.textLow,
                                  weight: FontWeight.w600,
                                  letterSpacing: 1.6)),
                          const Spacer(),
                          // Кнопка-крестик закрыть — для discoverability.
                          GestureDetector(
                            onTap: _close,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                borderRadius: AppTheme.borderRadius,
                                border: AppTheme.border(),
                              ),
                              child: Text('esc',
                                  style: AppTheme.mono(
                                      size: 9,
                                      color: AppColors.textLow,
                                      weight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: AppColors.bg,
                          borderRadius: AppTheme.borderRadius,
                          border: Border.all(
                            color: AppColors.acid,
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: controller,
                                focusNode: focus,
                                autofocus: true,
                                onChanged: _onChanged,
                                onSubmitted: _submit,
                                textInputAction: TextInputAction.search,
                                cursorColor: AppColors.acid,
                                style: const TextStyle(
                                    fontSize: 15,
                                    color: AppColors.textHi,
                                    fontWeight: FontWeight.w500),
                                decoration: InputDecoration(
                                  isCollapsed: true,
                                  border: InputBorder.none,
                                  hintText: placeholder,
                                  hintStyle: TextStyle(
                                      fontSize: 15,
                                      color: AppColors.textLow
                                          .withValues(alpha: 0.85)),
                                ),
                              ),
                            ),
                            const Icon(Icons.search,
                                size: 18, color: AppColors.textMid),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(
                    color: AppColors.border, height: 0.5, thickness: 0.5),
                Flexible(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: _Sections(
                        query: query,
                        actions: actions,
                        recents: recents,
                        onSelectAction: (a) {
                          a.run(context, ref);
                          _close();
                        },
                        onSelectRecent: (r) {
                          ref.read(omniboxControllerProvider).text = r;
                          ref.read(omniboxQueryProvider.notifier).set(r);
                          _navigate(
                              '/search?q=${Uri.encodeQueryComponent(r)}');
                        },
                        onSearchAll: () {
                          ref
                              .read(recentQueriesProvider.notifier)
                              .add(query);
                          _navigate(
                              '/search?q=${Uri.encodeQueryComponent(query)}');
                        },
                        onNavigate: _navigate,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Сматчить query на доступные actions. Простой substring + alias-набор.
  List<_OmniboxAction> _matchedActions(String q) {
    if (q.isEmpty) return const [];
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
      if (m(const ['stats', 'statistics', 'history']))
        _OmniboxAction(
          icon: Icons.bar_chart,
          label: 'view listening stats',
          run: (c, _) => c.go('/stats'),
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

class _Sections extends ConsumerWidget {
  const _Sections({
    required this.query,
    required this.actions,
    required this.recents,
    required this.onSelectAction,
    required this.onSelectRecent,
    required this.onSearchAll,
    required this.onNavigate,
  });

  final String query;
  final List<_OmniboxAction> actions;
  final List<String> recents;
  final void Function(_OmniboxAction) onSelectAction;
  final void Function(String) onSelectRecent;
  final VoidCallback onSearchAll;
  final void Function(String location, {bool push}) onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = <Widget>[];

    if (query.isEmpty) {
      if (recents.isNotEmpty) {
        sections.add(_Section(
          title: 'recent',
          children: [
            for (final r in recents)
              _Row(
                icon: Icons.history,
                title: r,
                onTap: () => onSelectRecent(r),
              ),
          ],
        ));
      } else {
        sections.add(const _EmptyHint(
            text:
                'type to search SoundCloud — or try “settings”, “logs”, “stats”'));
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
                onTap: () => onSelectAction(a),
              ),
          ],
        ));
      }

      final results = ref.watch(searchProvider(query));
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
              onTap: () => onNavigate('/track/${t.id}'),
            ));
          }
          for (final p in r.playlists.take(2)) {
            picks.add(_Row(
              icon: Icons.library_music_outlined,
              title: p.title,
              subtitle: p.subtitle,
              onTap: () => onNavigate('/playlist/${p.id}'),
            ));
          }
          for (final a in r.artists.take(2)) {
            picks.add(_Row(
              icon: Icons.person_outline,
              title: a.name,
              subtitle: '@${a.handle}',
              onTap: () => onNavigate(
                  '/artist/${Uri.encodeComponent(a.handle)}'),
            ));
          }
          if (picks.isNotEmpty) {
            sections.add(_Section(title: 'from soundcloud', children: picks));
          }
        },
      );

      sections.add(_Row(
        icon: Icons.search,
        title: 'search "$query" →',
        accent: true,
        onTap: onSearchAll,
      ));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: sections,
    );
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
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
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

class _Row extends StatefulWidget {
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
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          color: _hover
              ? AppColors.textHi.withValues(alpha: 0.05)
              : Colors.transparent,
          child: Row(
            children: [
              Icon(widget.icon,
                  size: 16,
                  color: widget.accent
                      ? AppColors.acid
                      : AppColors.textMid),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: widget.accent
                                ? AppColors.acid
                                : AppColors.textHi)),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(widget.subtitle!,
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
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Text(text,
          style: AppTheme.mono(size: 11, color: AppColors.textMid)),
    );
  }
}
