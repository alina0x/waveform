// ignore_for_file: avoid_print
// Живой смоук api-v2: добываем client_id со страницы soundcloud.com,
// делаем реальный /search/tracks, парсим через наши DTO и мапперы.
// Запуск: dart run tool/live_smoke.dart [запрос]
//
// Не часть тест-сьюта (ходит в сеть). Чисто верификация подхода.
import 'package:dio/dio.dart';
import 'package:waveform_app/core/api/client_id_resolver.dart';
import 'package:waveform_app/core/api/dto/json.dart';
import 'package:waveform_app/core/api/dto/page_dto.dart';
import 'package:waveform_app/core/api/dto/track_dto.dart';
import 'package:waveform_app/core/api/mappers.dart';

Future<void> main(List<String> args) async {
  final q = args.isEmpty ? 'ambient' : args.join(' ');
  final dio = Dio();
  final ids = ClientIdResolver(dio);

  try {
    final cid = await ids.get();
    print('✓ client_id: ${cid.substring(0, 6)}…${cid.substring(cid.length - 4)}');

    final resp = await dio.get(
      'https://api-v2.soundcloud.com/search/tracks',
      queryParameters: {'client_id': cid, 'q': q, 'limit': 5},
    );
    final page = PageDto.parse(asMap(resp.data), TrackDto.fromJson);
    print('✓ /search/tracks "$q" → ${page.collection.length} результатов:\n');

    for (final dto in page.collection) {
      final t = dto.toDomain();
      final hls = dto.transcodings.any((x) => x.isHls) ? 'HLS' : 'progressive';
      print('  • ${t.title} — ${t.artist}  '
          '[${t.plays} plays · ${t.duration.inMinutes}m · $hls · '
          '${t.streamCandidates.length} sources]');
    }

    // Резолв стрима: transcoding.url + client_id → {url: <m3u8/mp3>}.
    // Это и есть то, что just_audio получит на вход (первый кандидат = HLS).
    final first = page.collection.firstWhere(
        (d) => d.toDomain().streamCandidates.isNotEmpty,
        orElse: () => page.collection.first);
    final transcoding = first.toDomain().streamUrl;
    if (transcoding != null) {
      try {
        final r = await dio.get(transcoding, queryParameters: {'client_id': cid});
        final url = asMap(r.data)['url'];
        final kind = (url is String && url.contains('.m3u8')) ? 'HLS m3u8' : 'progressive';
        print('\n✓ resolveStreamUrl → $kind:\n  ${url ?? '(none)'}');
      } catch (e) {
        final code = e is DioException ? e.response?.statusCode : null;
        print('\n✗ resolveStreamUrl failed → ${code ?? e}');
      }
    }

    // Эндпоинты агрегатов home()/library() — каждый независимо.
    Future<void> probe(String path, Map<String, dynamic> q) async {
      try {
        final r = await dio.get('https://api-v2.soundcloud.com$path',
            queryParameters: {'client_id': cid, ...q});
        final n = (asMap(r.data)['collection'] as List?)?.length ??
            (asMap(r.data).isNotEmpty ? 1 : 0);
        print('  ✓ $path → $n');
      } catch (e) {
        final code = e is DioException ? e.response?.statusCode : null;
        print('  ✗ $path → ${code ?? e}');
      }
    }

    // Личные коллекции в api-v2 — по /users/{id}/..., НЕ /me/... .
    // Проверяем на публичном юзере (лайки/подписки публичны).
    try {
      final su = await dio.get('https://api-v2.soundcloud.com/search/users',
          queryParameters: {'client_id': cid, 'q': 'flume', 'limit': 1});
      final id = asMap((asMap(su.data)['collection'] as List).first)['id'];
      print('\npersonal-collection endpoints (user $id):');
      await probe('/users/$id/track_likes', {'limit': 3});
      await probe('/users/$id/likes', {'limit': 3});
      await probe('/users/$id/followings', {'limit': 3});
      await probe('/users/$id/playlists_without_albums', {'limit': 3});
      await probe('/users/$id/playlists', {'limit': 3});
      await probe('/users/$id/albums', {'limit': 3});
    } catch (e) {
      print('  user-endpoint probe setup failed: $e');
    }

    print('\nendpoint probe:');
    await probe('/mixed-selections', {'limit': 5});
    await probe('/featured_tracks/top/soundcloud:genres:all-music', {'limit': 5});
    await probe('/search/albums', {'q': '2024', 'limit': 5});
    await probe('/search/playlists', {'q': 'mix', 'limit': 5});
    await probe('/search/users', {'q': 'radio', 'limit': 5});

    // Что внутри mixed-selections (реальные курированные шелфы домашней).
    try {
      final r = await dio.get('https://api-v2.soundcloud.com/mixed-selections',
          queryParameters: {'client_id': cid, 'limit': 5});
      final cols = asMap(r.data)['collection'] as List? ?? [];
      print('\nmixed-selections shelves:');
      for (final s in cols.take(6)) {
        final m = asMap(s);
        final items = asMap(m['items'])['collection'] as List? ?? [];
        print('  • ${m['title']}  (${items.length} items, kind=${m['kind']})');
      }
    } catch (e) {
      print('  mixed-selections detail failed: $e');
    }
    print('\n✓ chain OK: scrape client_id → api-v2 → DTO → domain');
  } catch (e) {
    print('✗ smoke failed: $e');
  }
}
