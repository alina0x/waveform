import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/colors.dart';
import '../../core/api/feeds.dart';
import '../../core/api/soundcloud_api.dart';
import '../../core/api/soundcloud_auth.dart';
import '../../shared/models/collection.dart';
import '../../shared/models/track.dart';
import '../../shared/widgets/async_view.dart';
import '../../shared/widgets/collection_card.dart';
import '../../shared/widgets/media_carousel.dart';
import '../../shared/widgets/rail_layout.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/skeleton_box.dart';
import 'widgets/track_feed_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeProvider);
    return RailLayout(
      child: AsyncView<HomeData>(
        value: home,
        onRetry: () => ref.invalidate(homeProvider),
        skeleton: (_) => const _HomeSkeleton(),
        data: (data) => _HomeBody(data: data),
      ),
    );
  }
}

/// Layout-плейсхолдер на первый пейнт: 1 фейк-feed-card (если бы был authed) +
/// 2 фейк-карусели. По форме совпадает с реальным контентом — пользователь
/// сразу видит «что-то будет тут», а не статичный спиннер.
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppTheme.pagePad,
          AppTheme.topBarHeight + 26, AppTheme.pagePad, AppTheme.playerHeight + 32),
      children: [
        const SkeletonBox(width: 140, height: 12),
        const SizedBox(height: AppTheme.headerGap),
        for (var i = 0; i < 2; i++) ...[
          _FeedCardSkeleton(),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: AppTheme.sectionGap - 12),
        for (var s = 0; s < 2; s++) ...[
          const SkeletonBox(width: 180, height: 12),
          const SizedBox(height: AppTheme.headerGap),
          SizedBox(
            height: 206,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 4,
              separatorBuilder: (_, _) => const SizedBox(width: 20),
              itemBuilder: (_, _) => SizedBox(
                width: 150,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonBox(width: 150, height: 150),
                    SizedBox(height: 10),
                    SkeletonBox(width: 110, height: 13),
                    SizedBox(height: 6),
                    SkeletonBox(width: 70, height: 11),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppTheme.sectionGap),
        ],
      ],
    );
  }
}

class _FeedCardSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppTheme.borderRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(width: 128, height: 128),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonBox(width: 80, height: 11),
                SizedBox(height: 8),
                SkeletonBox(width: 220, height: 18),
                SizedBox(height: 16),
                SkeletonBox(width: double.infinity, height: 36),
                SizedBox(height: 14),
                Row(children: [
                  SkeletonBox(width: 40, height: 11),
                  SizedBox(width: 12),
                  SkeletonBox(width: 40, height: 11),
                  SizedBox(width: 12),
                  SkeletonBox(width: 40, height: 11),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeBody extends ConsumerWidget {
  const _HomeBody({required this.data});

  final HomeData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authed = ref.watch(authControllerProvider).isAuthenticated;

    // Полки главной — реальные плейлисты/альбомы. Карточка сама ведёт по target
    // (плейлист/трек/артист) — никакого случайного трека из стрима.
    MediaCarousel carousel(String title, List<Collection> items) => MediaCarousel(
          title: title,
          height: 206,
          children: [
            for (final item in items) CollectionCard(item: item),
          ],
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppTheme.pagePad,
          AppTheme.topBarHeight + 26, AppTheme.pagePad, AppTheme.playerHeight + 32),
      children: [
        // Личная лента подписок — только залогиненным.
        if (authed && data.stream.isNotEmpty) ...[
          const SectionHeader(title: 'from your stream'),
          const SizedBox(height: AppTheme.headerGap),
          for (final Track t in data.stream)
            TrackFeedCard(track: t, queue: data.stream),
          const SizedBox(height: AppTheme.sectionGap - 12),
        ],
        // Полки с реальными заголовками от SoundCloud (mixed-selections).
        for (final shelf in data.shelves) ...[
          carousel(shelf.title, shelf.items),
          const SizedBox(height: AppTheme.sectionGap),
        ],
      ],
    );
  }
}
