import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/prefs_store.dart';

/// Настройки воспроизведения, персистятся в `prefs.json`.
/// `crossfade == 0` → чистый gapless (preload + мгновенный swap).
/// `crossfade > 0` → плавный fade-out/in между треками (1–6 сек).
class PlaybackPrefs {
  const PlaybackPrefs({this.crossfadeMs = 0});
  final int crossfadeMs;
  Duration get crossfade => Duration(milliseconds: crossfadeMs);

  PlaybackPrefs copyWith({int? crossfadeMs}) =>
      PlaybackPrefs(crossfadeMs: crossfadeMs ?? this.crossfadeMs);
}

class PlaybackPrefsController extends Notifier<PlaybackPrefs> {
  static const _store = PrefsStore();
  static const _keyCrossfade = 'playback_crossfade_ms';

  @override
  PlaybackPrefs build() {
    _restore();
    return const PlaybackPrefs();
  }

  Future<void> _restore() async {
    try {
      final raw = await _store.readString(_keyCrossfade);
      if (raw == null) return;
      final v = int.tryParse(raw);
      if (v != null) state = state.copyWith(crossfadeMs: v.clamp(0, 6000));
    } catch (_) {}
  }

  void setCrossfadeMs(int ms) {
    final v = ms.clamp(0, 6000);
    state = state.copyWith(crossfadeMs: v);
    unawaited(_safe(() => _store.writeString(_keyCrossfade, '$v')));
  }

  Future<void> _safe(Future<void> Function() op) async {
    try {
      await op();
    } catch (_) {}
  }
}

final playbackPrefsProvider =
    NotifierProvider<PlaybackPrefsController, PlaybackPrefs>(
        PlaybackPrefsController.new);
