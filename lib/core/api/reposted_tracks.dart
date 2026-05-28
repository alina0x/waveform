import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'soundcloud_api.dart';
import 'soundcloud_auth.dart';

/// Множество ID треков, репостнутых текущим пользователем. Зеркало
/// `likedTracksProvider`: подгружается из `/users/{id}/track_reposts`,
/// оптимистичный toggle с откатом при провале.
class RepostedTracksController extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.watch(authControllerProvider); // перезагрузка при login/logout
    _load();
    return const {};
  }

  Future<void> _load() async {
    final ids = await ref.read(soundcloudApiProvider).repostedTrackIds();
    state = ids;
  }

  bool isReposted(String id) => state.contains(id);

  Future<LikeOutcome> toggle(String trackId) async {
    final repost = !state.contains(trackId);
    state = repost ? {...state, trackId} : ({...state}..remove(trackId));
    final outcome =
        await ref.read(soundcloudApiProvider).setReposted(trackId, repost);
    if (outcome != LikeOutcome.ok) {
      state = repost ? ({...state}..remove(trackId)) : {...state, trackId};
    }
    return outcome;
  }
}

final repostedTracksProvider =
    NotifierProvider<RepostedTracksController, Set<String>>(
        RepostedTracksController.new);
