import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/player/player_controller.dart';

/// Мост между нашим [PlayerController] (Riverpod) и системными медиа-
/// контролами через `audio_service`. На macOS даёт now-playing в Control
/// Center, медиа-клавиши клавиатуры (▶︎❘❘ / ⏮ / ⏭), lockscreen audio;
/// на Windows — SystemMediaTransportControls; на Linux — MPRIS.
///
/// Используется однонаправленно:
/// 1. OS → handler (play/pause/seek/next/prev) → проксируется в наш плеер.
/// 2. PlayerController через `sync()` пушит обновлённый `mediaItem` +
///    `playbackState` в handler — OS видит свежие данные.
class WaveformAudioHandler extends BaseAudioHandler {
  ProviderContainer? container;

  PlayerController? get _pc =>
      container?.read(playerControllerProvider.notifier);
  PlayerState? get _state => container?.read(playerControllerProvider);

  @override
  Future<void> play() async {
    final s = _state;
    if (s == null) return;
    if (!s.isPlaying) _pc?.toggle();
  }

  @override
  Future<void> pause() async {
    final s = _state;
    if (s == null) return;
    if (s.isPlaying) _pc?.toggle();
  }

  @override
  Future<void> skipToNext() async => _pc?.next();

  @override
  Future<void> skipToPrevious() async => _pc?.previous();

  @override
  Future<void> seek(Duration position) async {
    final s = _state;
    if (s == null) return;
    final dur = s.track?.durationMs ?? 0;
    if (dur == 0) return;
    _pc?.seekFraction(position.inMilliseconds / dur);
  }

  /// Пушим текущее состояние плеера в OS — вызывается из PlayerController
  /// после каждого изменения `state`.
  void sync(PlayerState s) {
    final t = s.track;
    if (t != null) {
      mediaItem.add(MediaItem(
        id: t.id,
        title: t.title,
        artist: t.artist,
        duration: t.duration,
        artUri: t.coverUrl != null && t.coverUrl!.isNotEmpty
            ? Uri.tryParse(t.coverUrl!)
            : null,
      ));
    } else {
      mediaItem.add(null);
    }
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (s.isPlaying) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.ready,
      playing: s.isPlaying,
      updatePosition: s.position,
      bufferedPosition: s.buffered,
      speed: 1.0,
    ));
  }
}

/// Глобальная точка доступа к handler'у. Инициализируется в `main` ДО
/// создания ProviderContainer и затем читается через провайдер.
late WaveformAudioHandler _audioHandlerSingleton;
void setAudioHandlerSingleton(WaveformAudioHandler h) =>
    _audioHandlerSingleton = h;

final audioHandlerProvider =
    Provider<WaveformAudioHandler>((_) => _audioHandlerSingleton);
