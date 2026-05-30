import 'json.dart';
import 'playlist_dto.dart';
import 'track_dto.dart';
import 'user_dto.dart';

/// Пагинированный ответ api-v2: `{ collection: [...], next_href: "..." }`.
class PageDto<T> {
  const PageDto({required this.collection, this.nextHref});

  final List<T> collection;
  final String? nextHref;

  factory PageDto.parse(
    Map<String, dynamic> j,
    T Function(Map<String, dynamic>) item,
  ) => PageDto(
    collection: asMapList(j['collection']).map(item).toList(),
    nextHref: j['next_href'] as String?,
  );
}

/// Элемент ленты `/stream`: репост/пост трека или плейлиста.
class StreamItemDto {
  const StreamItemDto({
    required this.type,
    this.createdAt,
    this.actor,
    this.track,
    this.playlist,
  });

  final String type; // track / track-repost / playlist / playlist-repost
  final String? createdAt;
  final UserDto? actor;
  final TrackDto? track;
  final PlaylistDto? playlist;

  bool get isRepost => type.endsWith('-repost');
  bool get isTrack => type.startsWith('track');

  factory StreamItemDto.fromJson(Map<String, dynamic> j) {
    final track = j['track'];
    final playlist = j['playlist'];
    final user = j['user'];
    return StreamItemDto(
      type: asStr(j['type']),
      createdAt: j['created_at'] as String?,
      actor: user is Map ? UserDto.fromJson(asMap(user)) : null,
      track: track is Map ? TrackDto.fromJson(asMap(track)) : null,
      playlist: playlist is Map ? PlaylistDto.fromJson(asMap(playlist)) : null,
    );
  }
}
