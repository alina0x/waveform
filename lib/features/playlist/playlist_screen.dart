import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/colors.dart';
import '../../core/api/feeds.dart';
import '../../core/api/soundcloud_api.dart';
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
            CoverArt(seed: p.id, imageUrl: p.coverUrl, size: 180),
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
                  if (tracks.isNotEmpty) _PlayAll(tracks: tracks),
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
