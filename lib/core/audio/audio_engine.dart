import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

/// Абстракция звукового движка. PlayerController зависит только от неё —
/// не от just_audio напрямую, поэтому тесты подменяют движок заглушкой.
abstract interface class AudioEngine {
  /// Текущая позиция воспроизведения.
  Stream<Duration> get positionStream;

  /// Граница того, насколько вперёд буферизировано (для buffered-полоски
  /// на waveform). Может «дёргаться» назад при seek.
  Stream<Duration> get bufferedPositionStream;

  /// Реальный признак «играет» от движка (учитывает буферизацию/паузы ОС).
  Stream<bool> get playingStream;

  /// Эмитит, когда трек доиграл до конца.
  Stream<void> get completedStream;

  /// Загрузить источник по URL и начать воспроизведение.
  Future<void> load(String url);
  Future<void> pause();
  Future<void> resume();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> stop();
  void dispose();
}

/// Реализация на just_audio. HLS (m3u8) и progressive (mp3) проигрываются
/// нативным движком платформы (на macOS — AVPlayer).
class JustAudioEngine implements AudioEngine {
  final AudioPlayer _player = AudioPlayer();

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;

  @override
  Stream<bool> get playingStream => _player.playingStream;

  @override
  Stream<void> get completedStream => _player.processingStateStream
      .where((s) => s == ProcessingState.completed);

  @override
  Future<void> load(String url) async {
    await _player.setUrl(url);
    await _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.play();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> stop() => _player.stop();

  @override
  void dispose() => _player.dispose();
}

/// Единый звуковой движок на время жизни приложения.
/// Тесты переопределяют провайдер заглушкой, чтобы не дёргать плагин.
final audioEngineProvider = Provider<AudioEngine>((ref) {
  final engine = JustAudioEngine();
  ref.onDispose(engine.dispose);
  return engine;
});
