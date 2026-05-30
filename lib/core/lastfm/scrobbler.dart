import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/player/player_controller.dart';
import '../log/talker.dart';
import 'lastfm_constants.dart';
import 'lastfm_session.dart';

/// Слушает PlayerController и отправляет в Last.fm события:
/// - `track.updateNowPlaying` при смене трека (debounce 3s от старта, чтобы
///   skip-storm не превращался в десятки записей).
/// - `track.scrobble` когда трек проигран ≥50% длительности или ≥4 минут.
///
/// Активируется как сторонний listener; включается по факту наличия session_key.
class LastfmScrobbler {
  LastfmScrobbler(this._ref);
  final Ref _ref;

  String? _currentTrackId;
  DateTime? _trackStartedAt;
  bool _nowPlayingSent = false;
  bool _scrobbled = false;

  void start() {
    _ref.listen(playerControllerProvider, (prev, next) {
      final session = _ref.read(lastfmSessionProvider);
      if (session == null || !lastfmConfigured) return;
      final t = next.track;
      if (t == null) {
        _resetForNew(null);
        return;
      }
      // Сменился трек → готовим новый цикл.
      if (t.id != _currentTrackId) {
        _resetForNew(t.id);
      }
      // Условия now-playing: трек звучит и прошло хотя бы 3s — отфильтровывает
      // быстрые скиппы.
      final since = _trackStartedAt == null
          ? Duration.zero
          : DateTime.now().difference(_trackStartedAt!);
      if (!_nowPlayingSent && next.isPlaying && since.inSeconds >= 3) {
        _nowPlayingSent = true;
        _sendNowPlaying(t.artist, t.title, t.duration, session.key);
      }
      // Scrobble после 50% или 4 минут.
      if (!_scrobbled) {
        final played = next.position.inMilliseconds;
        final dur = t.durationMs;
        final reachedHalf = dur > 0 && played >= dur ~/ 2;
        final fourMin = played >= 4 * 60 * 1000;
        if (reachedHalf || fourMin) {
          _scrobbled = true;
          _sendScrobble(
            t.artist,
            t.title,
            t.duration,
            _trackStartedAt ?? DateTime.now(),
            session.key,
          );
        }
      }
    });
  }

  void _resetForNew(String? newId) {
    _currentTrackId = newId;
    _trackStartedAt = newId == null ? null : DateTime.now();
    _nowPlayingSent = false;
    _scrobbled = false;
  }

  Future<void> _sendNowPlaying(
    String artist,
    String title,
    Duration dur,
    String sessionKey,
  ) async {
    try {
      await _ref
          .read(lastfmClientProvider)
          .updateNowPlaying(
            artist: artist,
            track: title,
            duration: dur,
            sessionKey: sessionKey,
          );
    } catch (e, st) {
      _ref.read(talkerProvider).warning('lastfm nowPlaying failed', e, st);
    }
  }

  Future<void> _sendScrobble(
    String artist,
    String title,
    Duration dur,
    DateTime startedAt,
    String sessionKey,
  ) async {
    try {
      await _ref
          .read(lastfmClientProvider)
          .scrobble(
            artist: artist,
            track: title,
            duration: dur,
            startedAt: startedAt,
            sessionKey: sessionKey,
          );
      _ref.read(talkerProvider).info('lastfm scrobbled: $artist — $title');
    } catch (e, st) {
      _ref.read(talkerProvider).warning('lastfm scrobble failed', e, st);
    }
  }
}

/// Eager-инициализация скробблера: его provider read'ится из AppShell, и он
/// сам сидит на `ref.listen(playerControllerProvider)`. Возвращает true чтобы
/// дёргать через `ref.watch(_)` (значение не важно, только side-effect).
final lastfmScrobblerProvider = Provider<bool>((ref) {
  LastfmScrobbler(ref).start();
  return true;
});
