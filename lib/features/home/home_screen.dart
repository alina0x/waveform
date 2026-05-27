import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
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
        data: (data) => _HomeBody(data: data),
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
