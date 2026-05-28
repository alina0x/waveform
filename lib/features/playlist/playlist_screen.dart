import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/colors.dart';
import '../../core/api/feeds.dart';
import '../../core/api/providers.dart';
import '../../core/api/soundcloud_api.dart';
import '../../core/log/talker.dart';
import '../../shared/models/track.dart';
import '../../shared/widgets/async_view.dart';
import '../../shared/widgets/cover_art.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/track_row.dart';
import '../player/player_controller.dart';

class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(playlistProvider(id));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 940),
        child: AsyncView<PlaylistDetail>(
          value: detail,
          onRetry: () => ref.invalidate(playlistProvider(id)),
          data: (d) => _Body(detail: d),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.detail});
  final PlaylistDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = detail.playlist;
    final tracks = detail.tracks;
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppTheme.pagePad,
          AppTheme.topBarHeight + 20, AppTheme.pagePad, AppTheme.playerHeight + 32),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Pressable(
            onTap: () => context.canPop() ? context.pop() : context.go('/'),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.chevron_left, size: 18, color: AppColors.textMid),
              Text('back', style: AppTheme.mono(size: 12, color: AppColors.textMid)),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Hero(
              tag: 'cover-playlist-${p.id}',
              child: CoverArt(seed: p.id, imageUrl: p.coverUrl, size: 180),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.kind.name.toUpperCase(),
                      style: AppTheme.mono(size: 11, color: AppColors.acid)),
                  const SizedBox(height: 8),
                  Text(p.title,
                      style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textHi)),
                  const SizedBox(height: 8),
                  Text('by ${p.subtitle}',
                      style: AppTheme.mono(size: 12, color: AppColors.textMid)),
                  const SizedBox(height: 4),
                  Text('${tracks.length} of ${p.trackCount} tracks',
                      style: AppTheme.mono(size: 11, color: AppColors.textLow)),
                  const SizedBox(height: 16),
                  if (tracks.isNotEmpty)
                    Row(children: [
                      _PlayAll(tracks: tracks),
                      const SizedBox(width: 10),
                      _ShuffleAll(
                          playlistId: p.id,
                          loadedTracks: tracks,
                          totalCount: p.trackCount),
                    ]),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        const SectionHeader(title: 'tracks'),
        const SizedBox(height: AppTheme.headerGap),
        if (tracks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('tracks aren’t available for this set',
                style: AppTheme.mono(size: 12, color: AppColors.textLow)),
          )
        else
          for (final t in tracks) TrackRow(track: t, queue: tracks),
      ],
    );
  }
}

/// Shuffle-all: при необходимости догружает весь сет плейлиста через
/// `allPlaylistTracks` (батчевый `/tracks?ids=…`), перемешивает и запускает.
/// Решает проблему web-SoundCloud, где shuffle охватывает только подгруженное.
class _ShuffleAll extends ConsumerStatefulWidget {
  const _ShuffleAll({
    required this.playlistId,
    required this.loadedTracks,
    required this.totalCount,
  });

  final String playlistId;
  final List<Track> loadedTracks;
  final int totalCount;

  @override
  ConsumerState<_ShuffleAll> createState() => _ShuffleAllState();
}

class _ShuffleAllState extends ConsumerState<_ShuffleAll> {
  bool _busy = false;
  static final _rng = Random();

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Если уже всё загружено — не дёргаем сеть.
      final tracks = widget.loadedTracks.length >= widget.totalCount
          ? List<Track>.of(widget.loadedTracks)
          : await ref
              .read(soundcloudApiProvider)
              .allPlaylistTracks(widget.playlistId);
      if (tracks.isEmpty) return;
      tracks.shuffle(_rng);
      ref
          .read(playerControllerProvider.notifier)
          .play(tracks.first, queue: tracks);
    } catch (e, st) {
      ref.read(talkerProvider).warning('shuffle-all failed', e, st);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: _run,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            borderRadius: AppTheme.borderRadius, border: AppTheme.border()),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_busy ? Icons.more_horiz : Icons.shuffle,
              size: 16, color: AppColors.textHi),
          const SizedBox(width: 6),
          Text(_busy ? 'loading…' : 'shuffle all',
              style: AppTheme.mono(
                  size: 12,
                  color: AppColors.textHi,
                  weight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class _PlayAll extends ConsumerWidget {
  const _PlayAll({required this.tracks});
  final List<Track> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Pressable(
      onTap: () => ref
          .read(playerControllerProvider.notifier)
          .play(tracks.first, queue: tracks),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
            color: AppColors.acid, borderRadius: AppTheme.borderRadius),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.play_arrow, size: 18, color: AppColors.bg),
          const SizedBox(width: 6),
          Text('play',
              style: AppTheme.mono(
                  size: 12, color: AppColors.bg, weight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
