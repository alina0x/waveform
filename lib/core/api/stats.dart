import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/track.dart';
import '../log/talker.dart';
import 'providers.dart';

/// Агрегаты по личной истории прослушиваний (`/me/play-history`).
class ListeningStats {
  const ListeningStats({
    required this.totalPlays,
    required this.uniqueTracks,
    required this.uniqueArtists,
    required this.totalListened,
    required this.topArtists,
    required this.topGenres,
  });

  final int totalPlays;
  final int uniqueTracks;
  final int uniqueArtists;
  final Duration totalListened;
  final List<({String name, int count})> topArtists;
  final List<({String genre, int count})> topGenres;

  bool get isEmpty => totalPlays == 0;
}

/// Постранично тянем play-history (до 400 записей за раз — баланс времени и
/// глубины), группируем и считаем. Безопасно для анона: `historyPage` сам
/// возвращает [] если нет авторизации.
final statsProvider = FutureProvider<ListeningStats>((ref) async {
  final api = ref.read(soundcloudApiProvider);
  final log = ref.read(talkerProvider);
  final all = <Track>[];
  const pageSize = 50;
  const maxPages = 8;
  for (var i = 0; i < maxPages; i++) {
    final offset = i * pageSize;
    try {
      final page = await api.historyPage(limit: pageSize, offset: offset);
      if (page.isEmpty) break;
      all.addAll(page);
      if (page.length < pageSize) break;
    } catch (e, st) {
      log.warning('stats: page $i failed', e, st);
      break;
    }
  }
  return _aggregate(all);
});

ListeningStats _aggregate(List<Track> tracks) {
  if (tracks.isEmpty) {
    return const ListeningStats(
      totalPlays: 0,
      uniqueTracks: 0,
      uniqueArtists: 0,
      totalListened: Duration.zero,
      topArtists: [],
      topGenres: [],
    );
  }
  final uniqueIds = <String>{for (final t in tracks) t.id};
  final artistCounts = <String, int>{};
  final genreCounts = <String, int>{};
  var totalMs = 0;
  for (final t in tracks) {
    totalMs += t.durationMs;
    artistCounts.update(t.artist, (v) => v + 1, ifAbsent: () => 1);
    if (t.genre.isNotEmpty) {
      genreCounts.update(t.genre, (v) => v + 1, ifAbsent: () => 1);
    }
  }
  final artistsSorted = artistCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final genresSorted = genreCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return ListeningStats(
    totalPlays: tracks.length,
    uniqueTracks: uniqueIds.length,
    uniqueArtists: artistCounts.length,
    totalListened: Duration(milliseconds: totalMs),
    topArtists: [
      for (final e in artistsSorted.take(10)) (name: e.key, count: e.value),
    ],
    topGenres: [
      for (final e in genresSorted.take(8)) (genre: e.key, count: e.value),
    ],
  );
}
