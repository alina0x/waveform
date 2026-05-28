import 'dart:async';

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

  /// Подготовить следующий источник в «теневом» движке (для gapless / crossfade).
  /// На JustAudioEngine — `setUrl` на inactive `AudioPlayer`. Без play.
  /// Если null — отменяем preload.
  Future<void> preloadNext(String? url);

  /// Перейти на preload'ный источник. При [crossfade]>0 — плавный fade-in/out
  /// (оба движка играют параллельно во время рампы). При zero — мгновенный.
  /// Если preload не подготовлен — no-op.
  Future<void> swapToNext({Duration crossfade = Duration.zero});

  /// Готов ли preload (можно swap'аться). Полезно контроллеру решить — swap
  /// или fallback к обычной `load(next)`.
  bool get hasPreload;

  void dispose();
}

/// Реализация на just_audio с **двумя** `AudioPlayer`'ами (`_a`, `_b`),
/// чтобы поддерживать gapless и crossfade: один играет, второй preload'ит
/// следующий трек. `_active` указывает на текущий.
///
/// Стримы (`position/buffered/playing/completed`) пробрасываются через
/// собственные broadcast-контроллеры — downstream-слушатель (PlayerController)
/// не пересоздаёт подписки при swap'е.
class JustAudioEngine implements AudioEngine {
  final AudioPlayer _a = AudioPlayer();
  final AudioPlayer _b = AudioPlayer();
  late AudioPlayer _active = _a;
  AudioPlayer get _inactive => identical(_active, _a) ? _b : _a;

  // Целевая громкость пользователя (по этой возвращаемся после fade-in).
  double _userVolume = 1.0;

  bool _preloadReady = false;

  // Прокси-стримы.
  final _positionCtrl = StreamController<Duration>.broadcast();
  final _bufferedCtrl = StreamController<Duration>.broadcast();
  final _playingCtrl = StreamController<bool>.broadcast();
  final _completedCtrl = StreamController<void>.broadcast();

  StreamSubscription<Duration>? _posSub, _bufSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<ProcessingState>? _stateSub;

  JustAudioEngine() {
    _bindActive();
  }

  /// Перепривязать подписки к новому активному плееру.
  void _bindActive() {
    _posSub?.cancel();
    _bufSub?.cancel();
    _playingSub?.cancel();
    _stateSub?.cancel();
    _posSub = _active.positionStream.listen(_positionCtrl.add);
    _bufSub = _active.bufferedPositionStream.listen(_bufferedCtrl.add);
    _playingSub = _active.playingStream.listen(_playingCtrl.add);
    _stateSub = _active.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) _completedCtrl.add(null);
    });
  }

  @override
  Stream<Duration> get positionStream => _positionCtrl.stream;

  @override
  Stream<Duration> get bufferedPositionStream => _bufferedCtrl.stream;

  @override
  Stream<bool> get playingStream => _playingCtrl.stream;

  @override
  Stream<void> get completedStream => _completedCtrl.stream;

  @override
  Future<void> load(String url) async {
    // Новый источник на active — отменяем preload (если он был под старый
    // «следующий», теперь не актуален).
    _preloadReady = false;
    await _active.setUrl(url);
    await _active.setVolume(_userVolume);
    await _active.play();
  }

  @override
  Future<void> pause() => _active.pause();

  @override
  Future<void> resume() => _active.play();

  @override
  Future<void> seek(Duration position) => _active.seek(position);

  @override
  Future<void> setVolume(double volume) async {
    _userVolume = volume;
    await _active.setVolume(volume);
  }

  @override
  Future<void> stop() => _active.stop();

  @override
  Future<void> preloadNext(String? url) async {
    if (url == null || url.isEmpty) {
      _preloadReady = false;
      try {
        await _inactive.stop();
      } catch (_) {}
      return;
    }
    try {
      await _inactive.setUrl(url);
      await _inactive.setVolume(0); // crossfade-старт всегда от 0
      _preloadReady = true;
    } catch (_) {
      _preloadReady = false;
    }
  }

  @override
  bool get hasPreload => _preloadReady;

  @override
  Future<void> swapToNext({Duration crossfade = Duration.zero}) async {
    if (!_preloadReady) return;
    final from = _active;
    final to = _inactive;
    _preloadReady = false;

    if (crossfade <= Duration.zero) {
      // Gapless: мгновенный swap.
      await to.setVolume(_userVolume);
      await to.play();
      await from.pause();
      _active = to;
      _bindActive();
      return;
    }

    // Crossfade: оба играют, линейная рампа громкости.
    const stepMs = 50;
    final steps =
        (crossfade.inMilliseconds / stepMs).clamp(1, 10000).toInt();
    await to.setVolume(0);
    await to.play();
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      // Старый плавно гаснет, новый плавно набирает.
      await from.setVolume(_userVolume * (1 - t));
      await to.setVolume(_userVolume * t);
      await Future<void>.delayed(const Duration(milliseconds: stepMs));
    }
    await from.pause();
    _active = to;
    _bindActive();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _bufSub?.cancel();
    _playingSub?.cancel();
    _stateSub?.cancel();
    _positionCtrl.close();
    _bufferedCtrl.close();
    _playingCtrl.close();
    _completedCtrl.close();
    _a.dispose();
    _b.dispose();
  }
}

/// Единый звуковой движок на время жизни приложения.
/// Тесты переопределяют провайдер заглушкой, чтобы не дёргать плагин.
final audioEngineProvider = Provider<AudioEngine>((ref) {
  final engine = JustAudioEngine();
  ref.onDispose(engine.dispose);
  return engine;
});
