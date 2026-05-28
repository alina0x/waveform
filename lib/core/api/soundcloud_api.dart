import '../../shared/models/artist.dart';
import '../../shared/models/collection.dart';
import '../../shared/models/comment.dart';
import '../../shared/models/feed_post.dart';
import '../../shared/models/track.dart';

/// Агрегаты данных под конкретные экраны — один запрос = одно состояние загрузки.

/// Полка главной: заголовок (реальный, от SoundCloud) + карточки.
typedef Shelf = ({String title, List<Collection> items});

typedef HomeData = ({
  List<Track> stream,
  List<Shelf> shelves,
});

typedef LibraryData = ({
  List<Collection> recentlyPlayed,
  List<Collection> likes,
  List<Collection> playlists,
  List<Collection> albums,
  List<Collection> stations,
  List<Collection> following,
  List<Track> history,
});

typedef TrackDetail = ({
  Track track,
  List<Comment> comments,
  List<Track> related,
});

typedef ArtistProfile = ({
  Artist artist,
  List<Track> tracks,
  List<Collection> albums,
  List<Collection> playlists,
});

typedef RailData = ({
  Artist? me, // профиль залогиненного юзера (null — аноним)
  List<Track> likes, // последние лайкнутые (превью; шорткат в library/likes)
  List<Track> history,
});

typedef SearchResults = ({
  List<Track> tracks,
  List<Artist> artists,
  List<Collection> playlists,
});

/// Плейлист/альбом + его треки.
typedef PlaylistDetail = ({
  Collection playlist,
  List<Track> tracks,
});

/// Исход записи лайка. [blocked] — SoundCloud отклонил запрос (часто
/// анти-абуз/капча, особенно под VPN: 401/403/429) → можно предложить
/// верификацию в браузере. [failed] — прочая ошибка/нет авторизации.
enum LikeOutcome { ok, failed, blocked }

/// Контракт источника данных SoundCloud. UI зависит только от него,
/// не от способа получения (моки сейчас / api-v2 или официальный API потом).
abstract interface class SoundcloudApi {
  Future<HomeData> home();
  Future<LibraryData> library();
  Future<List<FeedPost>> feed();
  Future<TrackDetail> trackDetail(String id);
  Future<ArtistProfile> artistProfile(String handle);
  Future<SearchResults> search(String query);
  Future<PlaylistDetail> playlist(String id);

  /// Полный список треков плейлиста (через `/tracks?ids=…` догружаем те, что в
  /// ответе `/playlists/{id}` пришли «огрызками» с одним `id`). Порядок сохраняем.
  /// Тяжелее [playlist]; зовём только когда реально нужен весь сет (shuffle-all).
  Future<List<Track>> allPlaylistTracks(String id);

  Future<RailData> rail();

  /// Резолвит URL транскодинга ([Track.streamUrl]) в проигрываемый
  /// HLS/progressive URL (m3u8/mp3). null — если трек не проигрываем
  /// (мок-данные, не streamable, недоступный транскодинг).
  Future<String?> resolveStreamUrl(String transcodingUrl);

  /// Проверяет, что OAuth-токен опознаётся как пользовательский (`/me`).
  /// Используется при логине, чтобы не принять гостевой/просроченный токен.
  Future<bool> verifyToken(String token);

  /// ID треков, лайкнутых текущим пользователем (для подсветки «liked»).
  /// Аноним/ошибка → пустое множество.
  Future<Set<String>> likedTrackIds();

  /// Лайкнуть/снять лайк с трека (PUT/DELETE). См. [LikeOutcome]: при `blocked`
  /// UI может предложить пройти верификацию (капча/VPN), при `failed`/`blocked`
  /// — откатить оптимистичное изменение.
  Future<LikeOutcome> setLiked(String trackId, bool liked);
}
