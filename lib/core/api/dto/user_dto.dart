import 'json.dart';

/// SoundCloud api-v2 `user` объект.
class UserDto {
  const UserDto({
    required this.id,
    required this.username,
    required this.permalink,
    this.avatarUrl,
    this.followersCount = 0,
    this.followingsCount = 0,
    this.trackCount = 0,
    this.likesCount = 0,
    this.playlistCount = 0,
    this.verified = false,
    this.description,
  });

  final int id;
  final String username;
  final String permalink;
  final String? avatarUrl;
  final int followersCount;
  final int followingsCount;
  final int trackCount;

  /// Заполнены только у `/me` (у обычных user-объектов в выдаче — 0).
  final int likesCount;
  final int playlistCount;
  final bool verified;
  final String? description;

  factory UserDto.fromJson(Map<String, dynamic> j) => UserDto(
        id: asInt(j['id']),
        username: asStr(j['username']),
        permalink: asStr(j['permalink']),
        avatarUrl: j['avatar_url'] as String?,
        followersCount: asInt(j['followers_count']),
        followingsCount: asInt(j['followings_count']),
        trackCount: asInt(j['track_count']),
        // api-v2 называет лайки то likes_count, то public_favorites_count.
        likesCount: asInt(j['likes_count'] ?? j['public_favorites_count']),
        playlistCount: asInt(j['playlist_count']),
        verified: asBool(j['verified']),
        description: j['description'] as String?,
      );
}
