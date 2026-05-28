import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/liked_tracks.dart';
import '../../core/api/providers.dart';
import '../../core/api/soundcloud_api.dart';
import '../../core/audio/audio_engine.dart';
import '../../core/log/talker.dart';
import '../../shared/models/track.dart';

/// Событие «трек не проигрался» — для всплывающего уведомления в UI.
/// [seq] растёт с каждым событием, чтобы listener срабатывал и на повтор.
typedef Unplayable = ({int seq, String title, bool goPlus});

/// Состояние плеера. Прогресс/признак «играет» приходят из [AudioEngine]
/// (just_audio); очередь next/previous — реальный список с экрана.
class PlayerState {
  const PlayerState({
    this.track,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.buffered = Duration.zero,
    this.shuffle = false,
    this.repeat = false,
    this.liked = false,
    this.volume = 1.0,
    this.unplayable,
    this.queueVersion = 0,
  });

  final Track? track;
  final bool isPlaying;
  final Duration position;
  final Duration buffered;
  final bool shuffle;
  final bool repeat;
  final bool liked;
  final double volume;

  /// Монотонно растущий счётчик — bump'ится контроллером на любую мутацию
  /// очереди. UI слушает `select((s) => s.queueVersion)` и пере-читает
  /// `notifier.upcomingTracks` для актуального списка.
  final int queueVersion;

  /// Последний непроигравшийся трек (GO+/недоступен) — UI показывает уведомление.
  final Unplayable? unplayable;

  /// Доля воспроизведённого (0..1) — для оранжевой части waveform.
  double get progress {
    final total = track?.durationMs ?? 0;
    if (total == 0) return 0;
    return (position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  /// Доля буферизированного (0..1) — для серого тиера на waveform.
  double get bufferedFraction {
    final total = track?.durationMs ?? 0;
    if (total == 0) return 0;
    return (buffered.inMilliseconds / total).clamp(0.0, 1.0);
  }

  PlayerState copyWith({
    Track? track,
    bool? isPlaying,
    Duration? position,
    Duration? buffered,
    bool? shuffle,
    bool? repeat,
    bool? liked,
    double? volume,
    Unplayable? unplayable,
    int? queueVersion,
  }) =>
      PlayerState(
        track: track ?? this.track,
        isPlaying: isPlaying ?? this.isPlaying,
        position: position ?? this.position,
        buffered: buffered ?? this.buffered,
        shuffle: shuffle ?? this.shuffle,
        repeat: repeat ?? this.repeat,
        liked: liked ?? this.liked,
        volume: volume ?? this.volume,
        unplayable: unplayable ?? this.unplayable,
        queueVersion: queueVersion ?? this.queueVersion,
      );
}

class PlayerController extends Notifier<PlayerState> {
  AudioEngine get _engine => ref.read(audioEngineProvider);

  /// Очередь, из которой пришёл текущий трек (для next/previous).
  List<Track> _queue = const [];
  final List<StreamSubscription<dynamic>> _subs = [];

  /// Токен последней загрузки — отбрасываем резолв устаревшего трека,
  /// если пользователь быстро переключил на другой.
  int _loadToken = 0;

  /// Когда реально начали играть текущий источник — для защиты от
  /// «мгновенного completed» (битый HLS), который иначе устраивал skip-storm.
  DateTime? _startedAt;

  /// Подряд идущих непроигрываемых треков (нет DRM-free источника). Ограничивает
  /// авто-переход на следующий, чтобы цепочка мёртвых треков не пролистала всё.
  int _deadStreak = 0;
  static const _maxDeadSkips = 3;

  @override
  PlayerState build() {
    final engine = ref.watch(audioEngineProvider);

    _subs.add(engine.positionStream.listen((p) {
      if (state.track != null) state = state.copyWith(position: p);
    }));
    _subs.add(engine.bufferedPositionStream.listen((b) {
      if (state.track != null) state = state.copyWith(buffered: b);
    }));
    _subs.add(engine.playingStream.listen((playing) {
      if (state.track != null && state.isPlaying != playing) {
        state = state.copyWith(isPlaying: playing);
      }
    }));
    _subs.add(engine.completedStream.listen((_) {
      // Ложный «completed» сразу после загрузки (битый HLS) НЕ должен
      // перескакивать дальше — иначе очередь пролистывается за секунды.
      // Реальный конец трека = играли заметное время И дошли почти до конца.
      final since = _startedAt == null
          ? Duration.zero
          : DateTime.now().difference(_startedAt!);
      final dur = state.track?.durationMs ?? 0;
      final played = state.position.inMilliseconds;
      final reachedEnd = dur > 0 ? played >= dur * 0.85 : played > 3000;
      if (since.inSeconds < 5 || !reachedEnd) return;
      if (state.repeat) {
        _engine.seek(Duration.zero);
        _engine.resume();
      } else {
        next();
      }
    }));

    // Подсветка «liked» в плеере держится в синхроне с реальным множеством
    // лайков (могло догрузиться после play или измениться из списка).
    ref.listen(likedTracksProvider, (_, liked) {
      final id = state.track?.id;
      if (id != null) {
        final isLiked = liked.contains(id);
        if (state.liked != isLiked) state = state.copyWith(liked: isLiked);
      }
    });

    ref.onDispose(() {
      for (final s in _subs) {
        s.cancel();
      }
      _subs.clear();
    });
    return const PlayerState();
  }

  /// Запустить трек. [queue] — список-контекст для next/previous;
  /// без него очередью становится сам трек.
  void play(Track track, {List<Track>? queue}) {
    _queue = (queue != null && queue.isNotEmpty) ? queue : [track];
    _orderSource = null; // queue сменилась → пересоберём шафл при необходимости
    state = state.copyWith(
      track: track,
      isPlaying: true,
      position: Duration.zero,
      // Подсветка лайка — из реального множества лайков (а не сброс в false).
      liked: ref.read(likedTracksProvider).contains(track.id),
      queueVersion: state.queueVersion + 1,
    );
    _load(track);
  }

  // ── Публичная queue-API (для queue-панели) ──────────────────────────────
  /// Текущий список «дальше будет» — без проигрываемого. В shuffle —
  /// из тасованного `_order`, иначе линейный хвост `_queue` от current'а.
  List<Track> get upcomingTracks {
    if (state.shuffle &&
        _order.isNotEmpty &&
        identical(_orderSource, _queue)) {
      final i = _order.indexWhere((t) => t.id == state.track?.id);
      if (i == -1) return List.unmodifiable(_order);
      return List.unmodifiable(_order.skip(i + 1));
    }
    final i = _queue.indexWhere((t) => t.id == state.track?.id);
    if (i == -1) return List.unmodifiable(_queue);
    return List.unmodifiable(_queue.skip(i + 1));
  }

  /// Индекс играющего в основной `_queue`; −1 если нет в очереди.
  int get currentQueueIndex =>
      _queue.indexWhere((t) => t.id == state.track?.id);

  /// Переставить трек в upcoming-секции. Индексы — в координатах списка
  /// `upcomingTracks` (0 = первый после current), внутри транслируется в
  /// абсолютные индексы `_queue`.
  void reorderUpcoming(int upcomingOld, int upcomingNew) {
    final cur = currentQueueIndex;
    if (cur < 0) return;
    final base = cur + 1;
    final oldAbs = base + upcomingOld;
    var newAbs = base + upcomingNew;
    if (oldAbs < base || oldAbs >= _queue.length) return;
    if (newAbs > _queue.length) newAbs = _queue.length;
    if (newAbs > oldAbs) newAbs -= 1; // ReorderableListView соглашение
    final item = _queue.removeAt(oldAbs);
    _queue.insert(newAbs, item);
    _orderSource = null;
    state = state.copyWith(queueVersion: state.queueVersion + 1);
  }

  /// Убрать трек из очереди (нельзя текущий — он играет).
  void removeFromQueue(String trackId) {
    if (trackId == state.track?.id) return;
    final n = _queue.length;
    _queue.removeWhere((t) => t.id == trackId);
    if (_queue.length == n) return;
    _orderSource = null;
    state = state.copyWith(queueVersion: state.queueVersion + 1);
  }

  /// Добавить трек в конец очереди; игнорим дубликат.
  void addToQueue(Track t) {
    if (_queue.any((x) => x.id == t.id)) {
      // Можно «поднять» наверх; пока проще no-op для дубликата.
      return;
    }
    _queue.add(t);
    _orderSource = null;
    state = state.copyWith(queueVersion: state.queueVersion + 1);
  }

  /// Резолв стрима (transcoding → m3u8/mp3) и передача в движок.
  /// Перебирает кандидатов (HLS → progressive): часть HLS-ссылок протухает и
  /// отдаёт 404 — тогда играем следующий источник. Мок/не streamable — тихо.
  Future<void> _load(Track track) async {
    final token = ++_loadToken;
    final candidates = track.streamCandidates;
    // Нет незашифрованных источников: GO+ → сообщаем причину; иначе мок/не
    // streamable — тихо (UI оптимистичен, реальный «играет» придёт из движка).
    if (candidates.isEmpty) {
      if (track.goPlus) {
        ref.read(talkerProvider).warning('GO+ only (subscription): ${track.title}');
        _markUnplayable(token, track);
      }
      return;
    }
    final api = ref.read(soundcloudApiProvider);
    for (final candidate in candidates) {
      try {
        final url = await api.resolveStreamUrl(candidate);
        if (token != _loadToken) return; // пользователь уже переключил трек
        if (url == null) continue; // транскодинг протух — следующий кандидат
        await _engine.load(url);
        if (token != _loadToken) return;
        _startedAt = DateTime.now();
        _deadStreak = 0; // успешная загрузка сбрасывает счётчик мёртвых
        return; // успех
      } catch (e, st) {
        ref.read(talkerProvider).warning(
            'stream candidate failed: ${track.title}', e, st);
        if (token != _loadToken) return;
        // пробуем следующий источник
      }
    }
    // Все кандидаты исчерпаны. GO+ → свободный поток лишь сниппет/протух, полный
    // зашифрован; иначе трек удалён/недоступен.
    ref.read(talkerProvider).warning(track.goPlus
        ? 'GO+ only (subscription): ${track.title}'
        : 'no playable stream: ${track.title}');
    _markUnplayable(token, track);
  }

  /// Помечает текущий трек непроигрываемым (с видимой причиной — GO+/недоступен)
  /// и в очереди перескакивает на следующий, но не более [_maxDeadSkips] подряд,
  /// чтобы цепочка мёртвых/GO+ треков не пролистала всю очередь.
  void _markUnplayable(int token, Track track) {
    if (token != _loadToken || state.track?.id != track.id) return;
    state = state.copyWith(
      isPlaying: false,
      unplayable: (seq: ++_unplayableSeq, title: track.title, goPlus: track.goPlus),
    );
    if (_queue.length > 1 && ++_deadStreak < _maxDeadSkips) {
      next();
    }
  }

  int _unplayableSeq = 0;

  void setVolume(double volume) {
    final v = volume.clamp(0.0, 1.0);
    state = state.copyWith(volume: v);
    _engine.setVolume(v);
  }

  void toggleShuffle() => state = state.copyWith(shuffle: !state.shuffle);
  void toggleRepeat() => state = state.copyWith(repeat: !state.repeat);

  /// Лайк текущего трека: оптимистично в UI + запись в API через общий контроллер
  /// (listener синхронизирует обратно при провале/догрузке). Возвращает исход —
  /// UI показывает предложение верификации при [LikeOutcome.blocked].
  Future<LikeOutcome> toggleLike() async {
    final track = state.track;
    if (track == null) return LikeOutcome.failed;
    state = state.copyWith(liked: !state.liked);
    return ref.read(likedTracksProvider.notifier).toggle(track.id);
  }

  /// Следующий трек в очереди (с учётом shuffle).
  void next() {
    final track = _adjacent(1);
    if (track != null) play(track, queue: _queue);
  }

  /// Предыдущий трек (или начало текущего, если прошло >3с).
  void previous() {
    if (state.position.inSeconds > 3) {
      _engine.seek(Duration.zero);
      state = state.copyWith(position: Duration.zero);
      return;
    }
    final track = _adjacent(-1);
    if (track != null) play(track, queue: _queue);
  }

  final Random _rng = Random();

  /// Перетасованный порядок очереди для true-shuffle (полный охват без
  /// повторов внутри цикла), и очередь, на которой он построен.
  List<Track> _order = const [];
  List<Track>? _orderSource;

  Track? _adjacent(int dir) {
    if (_queue.isEmpty) return null;
    if (state.shuffle) return _shuffledAdjacent(dir);
    final idx = _queue.indexWhere((t) => t.id == state.track?.id);
    if (idx == -1) return _queue.first;
    return _queue[(idx + dir) % _queue.length];
  }

  /// Следующий/предыдущий в перетасованном порядке. Каждый трек звучит один
  /// раз за цикл; в конце цикла — новая перетасовка (текущий не идёт первым).
  Track? _shuffledAdjacent(int dir) {
    if (_queue.length <= 1) return _queue.isEmpty ? null : _queue.first;
    if (!identical(_orderSource, _queue) || _order.length != _queue.length) {
      _order = List.of(_queue)..shuffle(_rng);
      _orderSource = _queue;
    }
    var pos = _order.indexWhere((t) => t.id == state.track?.id);
    if (pos == -1) pos = 0;
    var nextPos = pos + dir;
    if (nextPos >= _order.length) {
      _order = List.of(_queue)..shuffle(_rng);
      _orderSource = _queue;
      if (_order.length > 1 && _order.first.id == state.track?.id) {
        _order.add(_order.removeAt(0)); // не повторять текущий сразу
      }
      nextPos = 0;
    } else if (nextPos < 0) {
      nextPos = _order.length - 1;
    }
    return _order[nextPos];
  }

  void toggle() {
    if (state.track == null) return;
    if (state.isPlaying) {
      _engine.pause();
      state = state.copyWith(isPlaying: false);
    } else {
      _engine.resume();
      state = state.copyWith(isPlaying: true);
    }
  }

  /// Перемотка по доле (клик по waveform).
  void seekFraction(double fraction) {
    final total = state.track?.durationMs ?? 0;
    if (total == 0) return;
    final pos = Duration(milliseconds: (fraction.clamp(0.0, 1.0) * total).round());
    _engine.seek(pos);
    state = state.copyWith(position: pos);
  }
}

final playerControllerProvider =
    NotifierProvider<PlayerController, PlayerState>(PlayerController.new);
