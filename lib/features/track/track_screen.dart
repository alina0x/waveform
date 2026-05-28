import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/colors.dart';
import '../../core/api/feeds.dart';
import '../../core/api/liked_tracks.dart';
import '../../core/api/reposted_tracks.dart';
import '../../core/api/soundcloud_api.dart';
import '../../shared/action_feedback.dart';
import '../../shared/url_share.dart';
import '../../shared/widgets/ambient_backdrop.dart';
import '../../shared/format.dart';
import '../../shared/models/comment.dart';
import '../../shared/models/track.dart';
import '../../shared/widgets/async_view.dart';
import '../../shared/widgets/cover_art.dart';
import '../../shared/widgets/empty_state.dart';
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
    // Follow-mode: если эта страница соответствует играющему треку и плеер
    // переключился на следующий — открываем страницу нового. Сравниваем
    // prev.id == trackId (мы были в синхроне), next.id != trackId
    // (плеер ушёл вперёд) → context.go. Если юзер сам перешёл на чужой
    // /track/X (prev.id != trackId), не таскаем — он смотрит другое.
    ref.listen<Track?>(
        playerControllerProvider.select((s) => s.track), (prev, next) {
      if (prev == null || next == null) return;
      if (next.id == trackId) return;
      if (prev.id == trackId) {
        context.go('/track/${next.id}');
      }
    });
    final detail = ref.watch(trackDetailProvider(trackId));
    final coverUrl = detail.asData?.value.track.coverUrl;
    // Full-width hero-баннер из обложки — на page-level (вне ConstrainedBox),
    // плавно сходит в фон страницы. Контент скроллится поверх.
    return Stack(
      children: [
        if (coverUrl != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AmbientBackdrop(imageUrl: coverUrl, height: 460),
          ),
        Positioned.fill(
          child: AsyncView<TrackDetail>(
            value: detail,
            onRetry: () => ref.invalidate(trackDetailProvider(trackId)),
            data: (d) => _TrackBody(detail: d),
          ),
        ),
      ],
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
    final buffered = isCurrent ? player.bufferedFraction : 0.0;
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
              buffered: buffered,
              markers: [
                for (final cm in comments) cm.fraction(track.durationMs)
              ],
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
            if (comments.isEmpty)
              const EmptyState(
                icon: Icons.chat_bubble_outline,
                title: 'no comments yet',
                compact: true,
              )
            else
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
    required this.buffered,
    required this.markers,
    required this.onPlay,
    required this.onSeek,
  });

  final Track track;
  final bool isPlaying;
  final double progress;
  final double buffered;
  final List<double> markers;
  final VoidCallback onPlay;
  final ValueChanged<double>? onSeek;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Hero(
          tag: 'cover-track-${track.id}',
          child: CoverArt(seed: track.id, imageUrl: track.coverUrl, size: 210),
        ),
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
                buffered: buffered,
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

class _ActionBar extends ConsumerStatefulWidget {
  const _ActionBar({required this.track});
  final Track track;

  @override
  ConsumerState<_ActionBar> createState() => _ActionBarState();
}

class _ActionBarState extends ConsumerState<_ActionBar> {
  // Локальные дельты для оптимистичного UI: показываем ±1 сразу при тапе,
  // откатываем если API ответила !ok.
  int _likesDelta = 0;
  int _repostsDelta = 0;

  Future<void> _toggleLike() async {
    final wasLiked = ref.read(likedTracksProvider).contains(widget.track.id);
    setState(() => _likesDelta += wasLiked ? -1 : 1);
    final outcome =
        await ref.read(likedTracksProvider.notifier).toggle(widget.track.id);
    if (outcome != LikeOutcome.ok) {
      // Контроллер уже откатил `liked`-set; здесь откатываем дельту счётчика.
      if (mounted) setState(() => _likesDelta += wasLiked ? 1 : -1);
    }
    if (mounted) showWriteOutcome(context, outcome, verb: 'like');
  }

  Future<void> _toggleRepost() async {
    final wasReposted =
        ref.read(repostedTracksProvider).contains(widget.track.id);
    setState(() => _repostsDelta += wasReposted ? -1 : 1);
    final outcome = await ref
        .read(repostedTracksProvider.notifier)
        .toggle(widget.track.id);
    if (outcome != LikeOutcome.ok) {
      if (mounted) setState(() => _repostsDelta += wasReposted ? 1 : -1);
    }
    if (mounted) showWriteOutcome(context, outcome, verb: 'repost');
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final liked = ref.watch(likedTracksProvider).contains(track.id);
    final reposted = ref.watch(repostedTracksProvider).contains(track.id);
    return Row(
      children: [
        _Action(
          icon: liked ? Icons.favorite : Icons.favorite_border,
          value: Fmt.count(track.likes + _likesDelta),
          active: liked,
          onTap: _toggleLike,
        ),
        _Action(
          icon: Icons.repeat,
          value: Fmt.count(track.reposts + _repostsDelta),
          active: reposted,
          onTap: _toggleRepost,
        ),
        _Action(
          icon: Icons.share_outlined,
          onTap: () => _share(context, track),
        ),
        _MoreAction(track: track),
        const Spacer(),
        const Icon(Icons.play_arrow, size: 13, color: AppColors.textLow),
        const SizedBox(width: 4),
        Text('${Fmt.count(track.plays)} plays · ${track.postedAt}',
            style: AppTheme.mono(size: 11, color: AppColors.textLow)),
      ],
    );
  }
}

/// Копирует permalink трека в системный clipboard; уведомляет тостом.
Future<void> _share(BuildContext context, Track track) async {
  final url = track.permalinkUrl;
  if (url == null || url.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surface2,
      content: Text("no shareable link for this track",
          style: AppTheme.mono(size: 12, color: AppColors.textHi)),
    ));
    return;
  }
  await copyToClipboard(context, url);
}

/// Меню «more»: copy link + open on SoundCloud. Disabled, если permalink null.
class _MoreAction extends StatelessWidget {
  const _MoreAction({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) {
    final url = track.permalinkUrl;
    final enabled = url != null && url.isNotEmpty;
    return PopupMenuButton<String>(
      enabled: enabled,
      tooltip: 'more',
      offset: const Offset(0, 28),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppTheme.borderRadius,
        side: const BorderSide(color: AppColors.border, width: AppTheme.borderWidth),
      ),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'copy',
          child: Text('copy link',
              style: AppTheme.mono(size: 12, color: AppColors.textHi)),
        ),
        PopupMenuItem(
          value: 'open',
          child: Text('open on soundcloud ↗',
              style: AppTheme.mono(size: 12, color: AppColors.textHi)),
        ),
      ],
      onSelected: (v) async {
        if (url == null) return;
        if (v == 'copy') {
          if (context.mounted) await copyToClipboard(context, url);
        } else if (v == 'open') {
          await openExternalUrl(url);
        }
      },
      child: const Padding(
        padding: EdgeInsets.only(right: 18),
        child: Icon(Icons.more_horiz, size: 18, color: AppColors.textMid),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(
      {required this.icon, this.value, this.active = false, this.onTap});
  final IconData icon;
  final String? value;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.acid : AppColors.textMid;
    return Pressable(
      onTap: onTap ?? () {},
      child: Padding(
        padding: const EdgeInsets.only(right: 18),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
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
