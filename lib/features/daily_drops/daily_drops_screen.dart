import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/colors.dart';
import '../../core/api/feeds.dart';
import '../../core/api/soundcloud_auth.dart';
import '../../shared/models/track.dart';
import '../../shared/widgets/async_view.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/logged_out_view.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/rail_layout.dart';
import '../../shared/widgets/track_row.dart';
import '../player/player_controller.dart';

/// "Daily drops" — personalized "new for you" playlist surfaced as a top-bar
/// tab. Mirrors the shape of [FeedScreen]: rail layout, auth gate, async
/// view with empty state, pull-to-refresh.
class DailyDropsScreen extends ConsumerWidget {
  const DailyDropsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authed = ref.watch(authControllerProvider).isAuthenticated;
    if (!authed) {
      return const RailLayout(
        child: LoggedOutView(
          title: 'daily drops',
          subtitle:
              'log in to see your personalized "new for you" playlist, refreshed daily by soundcloud',
        ),
      );
    }
    final drops = ref.watch(dailyDropsProvider);
    return RailLayout(
      child: AsyncView<List<Track>>(
        value: drops,
        onRetry: () => ref.invalidate(dailyDropsProvider),
        data: (tracks) => RefreshIndicator(
          color: AppColors.acid,
          backgroundColor: AppColors.surface,
          onRefresh: () async {
            ref.invalidate(dailyDropsProvider);
            // Wait for the rebuild so the spinner stays up until data arrives.
            await ref.read(dailyDropsProvider.future);
          },
          child: tracks.isEmpty
              ? ListView(
                  // `ListView` (not Padding+Column) so RefreshIndicator gets a
                  // scrollable to attach to even when the empty state fits
                  // on one screen.
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.pagePad,
                    AppTheme.topBarHeight + 26,
                    AppTheme.pagePad,
                    AppTheme.playerHeight + 32,
                  ),
                  children: const [
                    _DailyDropsIntro(trackCount: 0),
                    SizedBox(height: 40),
                    EmptyState(
                      icon: Icons.auto_awesome_outlined,
                      title: 'no fresh drops today',
                      subtitle:
                          "soundcloud hasn't built your daily mix yet — like a few tracks and check back later",
                    ),
                  ],
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.pagePad,
                    AppTheme.topBarHeight + 26,
                    AppTheme.pagePad,
                    AppTheme.playerHeight + 32,
                  ),
                  children: [
                    _DailyDropsIntro(trackCount: tracks.length),
                    const SizedBox(height: 20),
                    for (final track in tracks)
                      TrackRow(track: track, queue: tracks),
                  ],
                ),
        ),
      ),
    );
  }
}

class _DailyDropsIntro extends ConsumerWidget {
  const _DailyDropsIntro({required this.trackCount});

  final int trackCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'daily drops',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textHi,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                trackCount == 0
                    ? 'fresh tracks picked for you every day'
                    : '$trackCount tracks · refreshed daily by soundcloud',
                style: AppTheme.mono(size: 12, color: AppColors.textMid),
              ),
            ],
          ),
        ),
        if (trackCount > 0) _PlayAllButton(),
      ],
    );
  }
}

class _PlayAllButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Pressable(
      onTap: () {
        // Read the provider synchronously — `dailyDropsProvider` is already
        // resolved by the time this button shows (gated on trackCount > 0).
        final tracks = ref.read(dailyDropsProvider).value;
        if (tracks == null || tracks.isEmpty) return;
        ref
            .read(playerControllerProvider.notifier)
            .play(tracks.first, queue: tracks);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.acid,
          borderRadius: AppTheme.borderRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_arrow, size: 16, color: AppColors.bg),
            const SizedBox(width: 6),
            Text(
              'play all',
              style: AppTheme.mono(
                size: 12,
                color: AppColors.bg,
                weight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
