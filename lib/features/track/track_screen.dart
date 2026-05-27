import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/colors.dart';
import '../../core/api/feeds.dart';
import '../../core/api/soundcloud_api.dart';
import '../../shared/action_feedback.dart';
import '../../shared/format.dart';
import '../../shared/models/comment.dart';
import '../../shared/models/track.dart';
import '../../shared/widgets/async_view.dart';
import '../../shared/widgets/cover_art.dart';
import '../../shared/widgets/go_plus_badge.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/track_row.dart';
import '../../shared/widgets/waveform_view.dart';
import '../player/player_controller.dart';

class TrackScreen extends ConsumerWidget {
  const TrackScreen({super.key, required this.trackId});

  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(trackDetailProvider(trackId));
    return AsyncView<TrackDetail>(
      value: detail,
      onRetry: () => ref.invalidate(trackDetailProvider(trackId)),
      data: (d) => _TrackBody(detail: d),
    );
  }
}

class _TrackBody extends ConsumerWidget {
  const _TrackBody({required this.detail});

  final TrackDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = detail.track;
    final comments = detail.comments;
    final player = ref.watch(playerControllerProvider);
    final c = ref.read(playerControllerProvider.notifier);
    final isCurrent = player.track?.id == track.id;
    final isPlaying = isCurrent && player.isPlaying;
    final progress = isCurrent ? player.progress : 0.0;
    final queue = [track, ...detail.related];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 940),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppTheme.pagePad,
              AppTheme.topBarHeight + 20, AppTheme.pagePad, AppTheme.playerHeight + 32),
          children: [
            const _BackButton(),
            const SizedBox(height: 16),
            _Hero(
              track: track,
              isPlaying: isPlaying,
              progress: progress,
              markers: [for (final cm in comments) cm.fraction(track.durationMs)],
              onPlay: () =>
                  isCurrent ? c.toggle() : c.play(track, queue: queue),
              onSeek: isCurrent ? c.seekFraction : null,
            ),
            const SizedBox(height: 24),
            if (track.description.isNotEmpty) ...[
              Text(track.description,
                  style: const TextStyle(
                      fontSize: 14, height: 1.6, color: AppColors.textMid)),
              const SizedBox(height: 28),
            ],
            SectionHeader(title: 'comments · ${comments.length}'),
            const SizedBox(height: AppTheme.headerGap),
            for (final cm in comments)
              _CommentRow(comment: cm, trackMs: track.durationMs),
            const SizedBox(height: 28),
            const SectionHeader(title: 'related tracks'),
            const SizedBox(height: AppTheme.headerGap),
            for (final t in detail.related) TrackRow(track: t, queue: queue),
          ],
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Pressable(
        onTap: () => context.canPop() ? context.pop() : context.go('/'),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chevron_left, size: 18, color: AppColors.textMid),
            Text('back', style: AppTheme.mono(size: 12, color: AppColors.textMid)),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.track,
    required this.isPlaying,
    required this.progress,
    required this.markers,
    required this.onPlay,
    required this.onSeek,
  });

  final Track track;
  final bool isPlaying;
  final double progress;
  final List<double> markers;
  final VoidCallback onPlay;
  final ValueChanged<double>? onSeek;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CoverArt(seed: track.id, imageUrl: track.coverUrl, size: 210),
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Pressable(
                    onTap: track.goPlus ? () => showGoPlusNotice(context) : onPlay,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                          color: track.goPlus
                              ? AppColors.surface2
                              : AppColors.acid,
                          shape: BoxShape.circle),
                      child: Icon(
                          track.goPlus
                              ? Icons.lock
                              : (isPlaying ? Icons.pause : Icons.play_arrow),
                          color: track.goPlus ? AppColors.textLow : AppColors.bg,
                          size: track.goPlus ? 26 : 32),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Pressable(
                              onTap: () => context.go(
                                  '/artist/${Uri.encodeComponent(track.artistHandle)}'),
                              child: Text(track.artist,
                                  style: AppTheme.mono(
                                      size: 12, color: AppColors.textMid)),
                            ),
                            if (track.goPlus) ...[
                              const SizedBox(width: 10),
                              const GoPlusBadge(),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(track.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                height: 1.1,
                                color: AppColors.textHi)),
                      ],
                    ),
                  ),
                  _TagChip(text: '#${track.genre}'),
                ],
              ),
              const SizedBox(height: 18),
              WaveformView(
                bars: track.waveform,
                progress: progress,
                height: 84,
                markers: markers,
                onSeek: onSeek,
              ),
              const SizedBox(height: 14),
              _ActionBar(track: track),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Action(icon: Icons.favorite_border, value: Fmt.count(track.likes)),
        _Action(icon: Icons.repeat, value: Fmt.count(track.reposts)),
        const _Action(icon: Icons.share_outlined),
        const _Action(icon: Icons.more_horiz),
        const Spacer(),
        Icon(Icons.play_arrow, size: 13, color: AppColors.textLow),
        const SizedBox(width: 4),
        Text('${Fmt.count(track.plays)} plays · ${track.postedAt}',
            style: AppTheme.mono(size: 11, color: AppColors.textLow)),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, this.value});
  final IconData icon;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.only(right: 18),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.textMid),
            if (value != null) ...[
              const SizedBox(width: 5),
              Text(value!, style: AppTheme.mono(size: 11)),
            ],
          ],
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: AppTheme.borderRadius,
        border: AppTheme.border(),
      ),
      child: Text(text, style: AppTheme.mono(size: 11, color: AppColors.textMid)),
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment, required this.trackMs});
  final Comment comment;
  final int trackMs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoverArt(seed: comment.authorSeed, size: 28, circular: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(comment.author,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textHi)),
                    const SizedBox(width: 8),
                    Text('@ ${Fmt.time(Duration(milliseconds: comment.timecodeMs))}',
                        style: AppTheme.mono(size: 10, color: AppColors.acid)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(comment.text,
                    style: const TextStyle(fontSize: 13, color: AppColors.textMid)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
