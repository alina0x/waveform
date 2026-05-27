import 'track.dart';

enum FeedAction { posted, reposted }

/// Запись в ленте подписок: кто-то выложил или репостнул трек.
class FeedPost {
  const FeedPost({
    required this.id,
    required this.actor,
    required this.action,
    required this.timeAgo,
    required this.track,
    required this.tag,
    this.comments = 0,
  });

  final String id;
  final String actor;
  final FeedAction action;
  final String timeAgo;
  final Track track;
  final String tag;
  final int comments;

  String get actionLabel =>
      action == FeedAction.reposted ? 'reposted a track' : 'posted a track';

  String get actorSeed => 'actor-$id';
}
