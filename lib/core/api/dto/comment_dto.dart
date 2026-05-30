import 'json.dart';
import 'user_dto.dart';

/// SoundCloud api-v2 `comment` объект (привязан к таймкоду трека).
class CommentDto {
  const CommentDto({
    required this.id,
    required this.body,
    required this.timestampMs,
    required this.user,
    this.createdAt,
    this.trackId,
  });

  final int id;
  final String body;
  final int timestampMs; // позиция на дорожке
  final UserDto user;
  final String? createdAt;
  final int? trackId;

  factory CommentDto.fromJson(Map<String, dynamic> j) => CommentDto(
    id: asInt(j['id']),
    body: asStr(j['body']),
    timestampMs: asInt(j['timestamp']),
    user: UserDto.fromJson(asMap(j['user'])),
    createdAt: j['created_at'] as String?,
    trackId: j['track_id'] == null ? null : asInt(j['track_id']),
  );
}
