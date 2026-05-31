import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/feed_post.dart';
import '../../shared/models/track.dart';
import 'providers.dart';
import 'soundcloud_api.dart';

/// Провайдеры данных под экраны. Каждый — один `AsyncValue`
/// (loading / error / data). Источник (mock/http) скрыт за soundcloudApiProvider.

final homeProvider = FutureProvider<HomeData>(
  (ref) => ref.watch(soundcloudApiProvider).home(),
);

final libraryProvider = FutureProvider<LibraryData>(
  (ref) => ref.watch(soundcloudApiProvider).library(),
);

final feedProvider = FutureProvider<List<FeedPost>>(
  (ref) => ref.watch(soundcloudApiProvider).feed(),
);

/// Daily drops — personalized "new for you" playlist. Rebuilds on auth
/// change because `soundcloudApiProvider` rebuilds on auth change.
final dailyDropsProvider = FutureProvider<List<Track>>(
  (ref) => ref.watch(soundcloudApiProvider).dailyDrops(),
);

final trackDetailProvider = FutureProvider.family<TrackDetail, String>(
  (ref, id) => ref.watch(soundcloudApiProvider).trackDetail(id),
);

final artistProfileProvider = FutureProvider.family<ArtistProfile, String>(
  (ref, handle) => ref.watch(soundcloudApiProvider).artistProfile(handle),
);

final railProvider = FutureProvider<RailData>(
  (ref) => ref.watch(soundcloudApiProvider).rail(),
);

final searchProvider = FutureProvider.family<SearchResults, String>(
  (ref, query) => ref.watch(soundcloudApiProvider).search(query),
);

final playlistProvider = FutureProvider.family<PlaylistDetail, String>(
  (ref, id) => ref.watch(soundcloudApiProvider).playlist(id),
);
