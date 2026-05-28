import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/colors.dart';
import '../../core/api/feeds.dart';
import '../../core/api/soundcloud_api.dart';
import '../../core/api/soundcloud_auth.dart';
import '../../shared/format.dart';
import '../../shared/models/collection.dart';
import '../../shared/models/track.dart';
import '../../shared/view_mode.dart';
import '../../shared/widgets/async_view.dart';
import '../../shared/widgets/collection_card.dart';
import '../../shared/widgets/collection_row.dart';
import '../../shared/widgets/cover_art.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/logged_out_view.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/view_toggle.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, this.initialTab});

  /// Имя вкладки для deep-link (`/library?tab=likes`) — шорткаты из рейла.
  final String? initialTab;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  static const _tabs = [
    'overview',
    'likes',
    'playlists',
    'albums',
    'stations',
    'following',
    'history',
  ];
  late int _tab = _tabIndexOf(widget.initialTab);

  int _tabIndexOf(String? name) {
    final i = _tabs.indexOf(name ?? '');
    return i == -1 ? 0 : i;
  }

  @override
  void didUpdateWidget(LibraryScreen old) {
    super.didUpdateWidget(old);
    // Повторная навигация на /library?tab=… с уже открытым экраном.
    if (widget.initialTab != old.initialTab && widget.initialTab != null) {
      setState(() => _tab = _tabIndexOf(widget.initialTab));
    }
  }

  @override
  Widget build(BuildContext context) {
    final authed = ref.watch(authControllerProvider).isAuthenticated;
    if (!authed) {
      return const Padding(
        padding: EdgeInsets.only(top: AppTheme.topBarHeight),
        child: LoggedOutView(
          title: 'your library',
          subtitle: 'log in to see your likes, playlists, stations and history',
        ),
      );
    }
    final lib = ref.watch(libraryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppTheme.topBarHeight),
        _TabBar(
          tabs: _tabs,
          current: _tab,
          onSelect: (i) => setState(() => _tab = i),
          // На history-табе — список треков (не коллекций); тогл там нерелевантен.
          trailing: _tabs[_tab] == 'history' ? null : const ViewToggle(),
        ),
        Expanded(
          child: AsyncView<LibraryData>(
            value: lib,
            onRetry: () => ref.invalidate(libraryProvider),
            data: (data) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(AppTheme.pagePad, 24,
                  AppTheme.pagePad, AppTheme.playerHeight + 32),
              child: _body(data),
            ),
          ),
        ),
      ],
    );
  }

  Widget _body(LibraryData d) {
    EmptyState noneFor(String section, IconData icon, String subtitle) =>
        EmptyState(
          icon: icon,
          title: 'no $section yet',
          subtitle: subtitle,
          actionLabel: 'go explore →',
          onAction: () => context.go('/'),
        );

    switch (_tabs[_tab]) {
      case 'likes':
        if (d.likes.isEmpty) {
          return noneFor('likes', Icons.favorite_outline,
              'like tracks to build a personal collection here');
        }
        return _grid('likes', d.likes);
      case 'playlists':
        if (d.playlists.isEmpty) {
          return noneFor('playlists', Icons.queue_music_outlined,
              'create a playlist on SoundCloud — it appears here');
        }
        return _grid('playlists', d.playlists);
      case 'albums':
        return d.albums.isEmpty
            ? noneFor('albums', Icons.album_outlined,
                'liked albums show up here')
            : _grid('albums for you', d.albums);
      case 'stations':
        return d.stations.isEmpty
            ? noneFor('stations', Icons.radio_outlined,
                'follow artists / genres to seed personal stations')
            : _grid('your stations', d.stations);
      case 'following':
        return d.following.isEmpty
            ? noneFor('one followed', Icons.people_outline,
                'follow artists to see their releases first')
            : _grid('following', d.following);
      case 'history':
        if (d.history.isEmpty) {
          return const EmptyState(
            icon: Icons.history,
            title: 'no history yet',
            subtitle: 'tracks you played will show up here',
          );
        }
        return _HistoryList(tracks: d.history);
      case 'overview':
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _grid('recently played', d.recentlyPlayed),
            const SizedBox(height: AppTheme.sectionGap),
            _grid('likes', d.likes),
            const SizedBox(height: AppTheme.sectionGap),
            _grid('playlists', d.playlists),
          ],
        );
    }
  }

  Widget _grid(String title, List<Collection> items) {
    final mode = ref.watch(viewModeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title),
        const SizedBox(height: AppTheme.headerGap),
        if (mode == ViewMode.tiles)
          Wrap(
            spacing: 20,
            runSpacing: 24,
            children: [
              for (final item in items) CollectionCard(item: item),
            ],
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in items) CollectionRow(item: item),
            ],
          ),
      ],
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.tabs,
    required this.current,
    required this.onSelect,
    this.trailing,
  });

  final List<String> tabs;
  final int current;
  final ValueChanged<int> onSelect;

  /// Опциональный элемент справа (например, `ViewToggle`).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePad),
      decoration: const BoxDecoration(
        border: Border(bottom: AppTheme.borderSideStatic),
      ),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            _Tab(label: tabs[i], active: i == current, onTap: () => onSelect(i)),
          if (trailing != null) ...[
            const Spacer(),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? AppColors.acid : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? AppColors.textHi : AppColors.textMid,
          ),
        ),
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'history'),
        const SizedBox(height: AppTheme.headerGap),
        for (final t in tracks) _HistoryRow(track: t),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () => context.go('/track/${track.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppTheme.borderRadius,
          border: AppTheme.border(),
        ),
        child: Row(
          children: [
            CoverArt(seed: track.id, imageUrl: track.coverUrl, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textHi)),
                  const SizedBox(height: 3),
                  Text(track.artist,
                      style: AppTheme.mono(size: 11, color: AppColors.textMid)),
                ],
              ),
            ),
            Row(
              children: [
                const Icon(Icons.play_arrow, size: 13, color: AppColors.textLow),
                const SizedBox(width: 4),
                Text(Fmt.count(track.plays), style: AppTheme.mono(size: 11)),
                const SizedBox(width: 18),
                Text(Fmt.time(track.duration), style: AppTheme.mono(size: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
