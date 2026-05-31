import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:logging/logging.dart';

/// Structured engine error for UI/logs. `fatal: true` means "current
/// source cannot play" — PlayerController surfaces a notification and
/// stops waiting for a miracle.
typedef EngineError = ({String stage, String message, bool fatal});

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

  /// Any engine error/warning event: operation exceptions, backend
  /// errors (`PlayerException` from just_audio), stalled buffering.
  /// PlayerController subscribes so the UI stops being silent on failure.
  Stream<EngineError> get errorStream;

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
  /// Logs go through `package:logging`; `main.dart` bridges them into
  /// Talker so the engine stays free of UI/Riverpod dependencies.
  static final _log = Logger('JustAudioEngine');

  final AudioPlayer _a = AudioPlayer();

  /// Second player — lazy: constructed on first use (load/preloadNext).
  /// `just_audio_media_kit` README warns "the plugin hasn't been tested
  /// with multiple player instances". We don't spawn the extra mpv
  /// player until we actually need it.
  late final AudioPlayer _b = AudioPlayer();

  /// Whether `_b` has ever been materialized. If `_active == _a` and
  /// `_b` is still unborn, we MUST NOT read it — that would trigger the
  /// `late final` initializer and waste a libmpv instance.
  bool _bInitialized = false;

  late AudioPlayer _active = _a;
  AudioPlayer get _inactive => identical(_active, _a) ? _b : _a;

  // Целевая громкость пользователя (по этой возвращаемся после fade-in).
  double _userVolume = 1.0;

  bool _preloadReady = false;

  /// Поколение «переходных» операций (load/swap). Каждая новая операция
  /// инкрементит счётчик; долгая crossfade-рампа на каждой итерации сверяет
  /// своё поколение и прекращается, если её перебила более новая операция —
  /// иначе `_active` мог 6с указывать на старый (паузный) плеер, и громкость/
  /// прогресс/play-pause рулили «не тем» плеером (главный баг десинка).
  int _swapGen = 0;

  // Прокси-стримы.
  final _positionCtrl = StreamController<Duration>.broadcast();
  final _bufferedCtrl = StreamController<Duration>.broadcast();
  final _playingCtrl = StreamController<bool>.broadcast();
  final _completedCtrl = StreamController<void>.broadcast();
  final _errorCtrl = StreamController<EngineError>.broadcast();

  StreamSubscription<Duration>? _posSub, _bufSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<ProcessingState>? _stateSub;
  StreamSubscription<PlayerException>? _engineErrSub;

  /// Watchdog: if no `ready` arrives within 5 s of `load`/`swap`, the
  /// source is either dead or libmpv silently hung on the demuxer. We
  /// emit a fatal error so PlayerController marks the track unplayable
  /// and moves on instead of spinning forever.
  Timer? _loadWatchdog;
  static const _readyTimeout = Duration(seconds: 5);

  JustAudioEngine() {
    _bindActive();
  }

  /// Перепривязать подписки к новому активному плееру.
  void _bindActive() {
    _posSub?.cancel();
    _bufSub?.cancel();
    _playingSub?.cancel();
    _stateSub?.cancel();
    _engineErrSub?.cancel();
    _posSub = _active.positionStream.listen(_positionCtrl.add);
    _bufSub = _active.bufferedPositionStream.listen(_bufferedCtrl.add);
    _playingSub = _active.playingStream.listen(_playingCtrl.add);
    _stateSub = _active.processingStateStream.listen((s) {
      _log.fine('processingState: ${s.name}');
      if (s == ProcessingState.ready) _cancelWatchdog();
      if (s == ProcessingState.completed) _completedCtrl.add(null);
    });
    _engineErrSub = _active.errorStream.listen((err) {
      // PlayerException = "the backend says no". On Windows libmpv
      // reports broken HLS playlists and missing codecs this way.
      _log.warning('player error (${err.code}): ${err.message}');
      _emitError(
        stage: 'player',
        message: '(${err.code}) ${err.message ?? "unknown"}',
        fatal: true,
      );
      _cancelWatchdog();
    });
  }

  void _emitError({
    required String stage,
    required String message,
    required bool fatal,
  }) {
    if (_errorCtrl.isClosed) return;
    _errorCtrl.add((stage: stage, message: message, fatal: fatal));
  }

  void _cancelWatchdog() {
    _loadWatchdog?.cancel();
    _loadWatchdog = null;
  }

  void _armWatchdog(String stage) {
    _cancelWatchdog();
    _loadWatchdog = Timer(_readyTimeout, () {
      _log.warning('$stage: no ready within ${_readyTimeout.inSeconds}s');
      _emitError(
        stage: stage,
        message: 'no ready signal within ${_readyTimeout.inSeconds}s',
        fatal: true,
      );
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
  Stream<EngineError> get errorStream => _errorCtrl.stream;

  @override
  Future<void> load(String url) async {
    // Новая авторитетная загрузка отменяет любую идущую crossfade-рампу и
    // preload (он был под старый «следующий»).
    ++_swapGen;
    _preloadReady = false;
    _armWatchdog('load');
    // Mute the shadow player so a paused crossfade doesn't leave a
    // "ghost" stream running. Only touch `_inactive` if `_b` already
    // exists — otherwise we'd materialize it for nothing.
    if (_hasInactive) {
      try {
        await _inactive.pause();
        await _inactive.setVolume(0);
      } catch (e) {
        _log.fine('inactive pause/mute on load failed: $e');
      }
    }
    try {
      await _active.setUrl(url);
      await _active.setVolume(_userVolume);
      // Явный seek(0): setUrl обычно сбрасывает позицию, но защищаемся от
      // унаследованной позиции у переиспользуемого AudioPlayer'а.
      await _active.seek(Duration.zero);
      await _active.play();
      _log.info('load OK: $url');
    } catch (e, st) {
      _cancelWatchdog();
      _log.severe('load failed: $url', e, st);
      _emitError(stage: 'load', message: '$e', fatal: true);
      rethrow;
    }
  }

  /// True iff there's an "other" player worth touching: `_a` is always
  /// alive, but `_b` is `late final` and we must not read it before it
  /// has been intentionally materialized.
  bool get _hasInactive {
    if (identical(_active, _a)) return _bInitialized;
    return true; // active is _b → _a is the other and always exists
  }

  AudioPlayer _materializeB() {
    if (!_bInitialized) {
      _bInitialized = true;
      _log.fine('materializing second AudioPlayer (preload/swap requested)');
    }
    return _b;
  }

  @override
  Future<void> pause() async {
    // Отменяем идущую crossfade-рампу — иначе она доиграет старый плеер и
    // докрутит громкости поверх нашей паузы.
    ++_swapGen;
    try {
      // Глушим ОБА плеера: во время crossfade старый (`from`) ещё звучит, и
      // пауза только `_active` оставляла бы его играющим («поставил на паузу —
      // а играет»). Пауза второго плеера идемпотентна, когда он и так стоит.
      await _a.pause();
      if (_bInitialized) await _b.pause();
      // Рампа могла оставить активный на промежуточной громкости — возвращаем.
      await _active.setVolume(_userVolume);
    } catch (e, st) {
      _log.warning('pause failed', e, st);
      _emitError(stage: 'pause', message: '$e', fatal: false);
      rethrow;
    }
  }

  @override
  Future<void> resume() async {
    try {
      await _active.play();
    } catch (e, st) {
      _log.warning('resume failed', e, st);
      _emitError(stage: 'resume', message: '$e', fatal: false);
      rethrow;
    }
  }

  @override
  Future<void> seek(Duration position) async {
    try {
      await _active.seek(position);
    } catch (e, st) {
      _log.warning('seek failed: $position', e, st);
      _emitError(stage: 'seek', message: '$e', fatal: false);
      rethrow;
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    _userVolume = volume;
    try {
      await _active.setVolume(volume);
    } catch (e, st) {
      _log.warning('setVolume failed: $volume', e, st);
      _emitError(stage: 'setVolume', message: '$e', fatal: false);
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    _cancelWatchdog();
    try {
      await _active.stop();
    } catch (e, st) {
      _log.warning('stop failed', e, st);
      _emitError(stage: 'stop', message: '$e', fatal: false);
      rethrow;
    }
  }

  @override
  Future<void> preloadNext(String? url) async {
    if (url == null || url.isEmpty) {
      _preloadReady = false;
      // No point stopping a player we never created.
      if (_hasInactive) {
        try {
          await _inactive.stop();
        } catch (e) {
          _log.fine('preloadNext(null) stop on inactive failed: $e');
        }
      }
      return;
    }
    // First preload materializes `_b`.
    if (identical(_active, _a)) _materializeB();
    try {
      await _inactive.setUrl(url);
      await _inactive.setVolume(0); // crossfade-старт всегда от 0
      _preloadReady = true;
      _log.fine('preload OK: $url');
    } catch (e, st) {
      _preloadReady = false;
      _log.warning('preload failed: $url', e, st);
      // NOT fatal: the active track keeps playing; we'll just fall back
      // to a full `load(next)` when the transition actually arrives.
      _emitError(stage: 'preload', message: '$e', fatal: false);
    }
  }

  @override
  bool get hasPreload => _preloadReady;

  @override
  Future<void> swapToNext({Duration crossfade = Duration.zero}) async {
    if (!_preloadReady) return;
    final gen = ++_swapGen;
    final from = _active;
    final to = _inactive;
    _preloadReady = false;
    _armWatchdog('swap');

    // ИНВАРИАНТ: `_active` указывает на плеер «текущего трека» сразу, ещё до
    // окончания рампы. Тогда громкость/позиция/play-pause всегда рулят новым
    // треком, а старый просто гаснет в фоне — даже если нас прервут.
    _active = to;
    _bindActive();
    try {
      // Защита от унаследованной позиции у preload'ного плеера.
      await to.seek(Duration.zero);

      if (crossfade <= Duration.zero) {
        // Gapless: мгновенный swap.
        await to.setVolume(_userVolume);
        await to.play();
        await from.pause();
        return;
      }

      // Crossfade: оба играют, линейная рампа громкости. Фон (`from`) гаснет,
      // передний (`to` = новый `_active`) набирает до _userVolume.
      const stepMs = 50;
      final steps = (crossfade.inMilliseconds / stepMs).clamp(1, 10000).toInt();
      await to.setVolume(0);
      await to.play();
      for (var i = 1; i <= steps; i++) {
        if (gen != _swapGen) return; // нас перебила новая load/swap — выходим
        final t = i / steps;
        await from.setVolume(_userVolume * (1 - t));
        await to.setVolume(_userVolume * t);
        await Future<void>.delayed(const Duration(milliseconds: stepMs));
      }
      if (gen != _swapGen) return;
      await from.pause();
      await to.setVolume(_userVolume);
    } catch (e, st) {
      _cancelWatchdog();
      _log.severe('swap failed', e, st);
      _emitError(stage: 'swap', message: '$e', fatal: true);
      rethrow;
    }
  }

  @override
  void dispose() {
    _cancelWatchdog();
    _posSub?.cancel();
    _bufSub?.cancel();
    _playingSub?.cancel();
    _stateSub?.cancel();
    _engineErrSub?.cancel();
    _positionCtrl.close();
    _bufferedCtrl.close();
    _playingCtrl.close();
    _completedCtrl.close();
    _errorCtrl.close();
    _a.dispose();
    if (_bInitialized) _b.dispose();
  }
}

/// Единый звуковой движок на время жизни приложения.
/// Тесты переопределяют провайдер заглушкой, чтобы не дёргать плагин.
final audioEngineProvider = Provider<AudioEngine>((ref) {
  final engine = JustAudioEngine();
  ref.onDispose(engine.dispose);
  return engine;
});
