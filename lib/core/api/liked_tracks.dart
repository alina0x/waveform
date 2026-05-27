import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'soundcloud_api.dart';
import 'soundcloud_auth.dart';

/// Множество ID треков, лайкнутых текущим пользователем. Единый источник правды
/// для подсветки «liked» в списках и в плеере. Перезагружается при смене логина.
class LikedTracksController extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.watch(authControllerProvider); // перезагрузка при login/logout
    _load();
    return const {};
  }

  Future<void> _load() async {
    final ids = await ref.read(soundcloudApiProvider).likedTrackIds();
    state = ids;
  }

  bool isLiked(String id) => state.contains(id);

  /// Оптимистично переключаем и пишем в API; при провале (нет авторизации /
  /// блокировка/капча) — откат к прежнему состоянию. Возвращает исход, чтобы UI
  /// мог показать предложение верификации при [LikeOutcome.blocked].
  Future<LikeOutcome> toggle(String trackId) async {
    final like = !state.contains(trackId);
    state = like ? {...state, trackId} : ({...state}..remove(trackId));
    final outcome = await ref.read(soundcloudApiProvider).setLiked(trackId, like);
    if (outcome != LikeOutcome.ok) {
      state = like ? ({...state}..remove(trackId)) : {...state, trackId};
    }
    return outcome;
  }
}

final likedTracksProvider =
    NotifierProvider<LikedTracksController, Set<String>>(
        LikedTracksController.new);
