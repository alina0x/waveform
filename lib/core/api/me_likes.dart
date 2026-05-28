import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/track.dart';
import 'providers.dart';

/// Состояние paginated-лайков: накопленный список + флаги загрузки + курсор.
/// SC api-v2 использует cursor-пагинацию (timestamp+type+id в `next_href`),
/// не числовой offset — отсюда [_nextHref] вместо `offset`.
class LikesPageState {
  const LikesPageState({
    this.tracks = const [],
    this.isInitial = true,
    this.isLoadingMore = false,
    this.nextHref,
    this.error,
  });

  final List<Track> tracks;
  final bool isInitial;
  final bool isLoadingMore;
  final String? nextHref;
  final Object? error;

  /// Есть ли смысл звать `loadNext()` ещё раз. На первой загрузке — да
  /// (nextHref ещё null, но isInitial=true). Позже nextHref=null означает
  /// «всё дочитано».
  bool get hasMore => isInitial || nextHref != null;

  LikesPageState copyWith({
    List<Track>? tracks,
    bool? isInitial,
    bool? isLoadingMore,
    String? nextHref,
    bool clearNextHref = false,
    Object? error,
    bool clearError = false,
  }) =>
      LikesPageState(
        tracks: tracks ?? this.tracks,
        isInitial: isInitial ?? this.isInitial,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        nextHref: clearNextHref ? null : (nextHref ?? this.nextHref),
        error: clearError ? null : (error ?? this.error),
      );
}

class MeLikesPageController extends Notifier<LikesPageState> {
  static const _pageSize = 50;

  @override
  LikesPageState build() {
    Future.microtask(loadNext);
    return const LikesPageState();
  }

  Future<void> loadNext() async {
    if (state.isLoadingMore || !state.hasMore) return;
    final api = ref.read(soundcloudApiProvider);
    state = state.copyWith(isLoadingMore: true, clearError: true);
    try {
      final result = await api.likesPage(
        nextHref: state.nextHref,
        limit: _pageSize,
      );
      // Дедуп на случай пересечений между страницами (или повторов от SC).
      final seen = {for (final t in state.tracks) t.id};
      final fresh = [for (final t in result.tracks) if (!seen.contains(t.id)) t];
      state = state.copyWith(
        tracks: [...state.tracks, ...fresh],
        isInitial: false,
        isLoadingMore: false,
        nextHref: result.nextHref,
        clearNextHref: result.nextHref == null,
      );
    } catch (e) {
      state = state.copyWith(
        isInitial: false,
        isLoadingMore: false,
        error: e,
      );
    }
  }

  /// Полный сброс — для pull-to-refresh / retry после ошибки.
  Future<void> reset() async {
    state = const LikesPageState();
    await loadNext();
  }
}

final meLikesPagedProvider =
    NotifierProvider<MeLikesPageController, LikesPageState>(
        MeLikesPageController.new);
