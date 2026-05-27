/// Исполнитель — для «who to follow», «new crew», шапок постов, станций.
class Artist {
  const Artist({
    required this.id,
    required this.handle,
    required this.followers,
    String? name,
    this.trackCount = 0,
    this.likesCount = 0,
    this.playlistCount = 0,
    this.followingsCount = 0,
    this.verified = false,
    this.avatarUrl,
  }) : name = name ?? handle;

  final String id;

  /// Permalink (URL-слаг) для роутинга `/artist/:handle` и resolve.
  final String handle;

  /// Отображаемое имя (username). По умолчанию = handle (моки).
  final String name;
  final int followers;
  final int trackCount;

  /// Личные счётчики (только для своего профиля `/me`) — для правого рейла.
  final int likesCount;
  final int playlistCount;
  final int followingsCount;
  final bool verified;
  final String? avatarUrl;

  String get coverSeed => 'artist-$id';
}
