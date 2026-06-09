import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:talker_flutter/talker_flutter.dart';

import '../log/talker.dart';

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
  JustAudioEngine(this._log, {AudioPlayer Function()? createPlayer})
    : _a = (createPlayer ?? AudioPlayer.new)(),
      _b = (createPlayer ?? AudioPlayer.new)() {
    _bindActive();
  }

  /// Talker для диагностики crossfade (виден в /logs).
  final Talker _log;

  final AudioPlayer _a;
  final AudioPlayer _b;
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

  StreamSubscription<Duration>? _posSub, _bufSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<ProcessingState>? _stateSub;

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

  /// Запускает воспроизведение, НЕ ожидая `play()`-future. У just_audio она
  /// завершается лишь когда воспроизведение ОСТАНАВЛИВАЕТСЯ (pause/stop/
  /// completed) — `await player.play()` заблокировал бы всё, что идёт следом:
  /// рампу crossfade'а, `from.pause()`, продолжение `_load`. Гард
  /// `if (playing) return` в just_audio спасал `load()` (там плеер обычно уже
  /// играет), но НЕ swap: preload'ный плеер ещё не играет, и await висел до
  /// конца трека → входящий оставался на нулевой громкости (тихий трек).
  void _play(AudioPlayer p) {
    unawaited(
      p.play().catchError((Object e, StackTrace st) {
        _log.error('[engine] play() failed', e, st);
      }),
    );
  }

  @override
  Future<void> load(String url) async {
    // Новая авторитетная загрузка отменяет любую идущую crossfade-рампу и
    // preload (он был под старый «следующий»).
    ++_swapGen;
    _log.debug('[engine] load → gen=$_swapGen');
    _preloadReady = false;
    // Глушим теневой плеер — чтобы не остался «призрачный» звук от
    // прерванного crossfade'а.
    try {
      await _inactive.pause();
      await _inactive.setVolume(0);
    } catch (_) {}
    await _active.setUrl(url);
    await _active.setVolume(_userVolume);
    // Явный seek(0): setUrl обычно сбрасывает позицию, но защищаемся от
    // унаследованной позиции у переиспользуемого AudioPlayer'а.
    await _active.seek(Duration.zero);
    _play(_active);
  }

  @override
  Future<void> pause() async {
    // Отменяем идущую crossfade-рампу — иначе она доиграет старый плеер и
    // докрутит громкости поверх нашей паузы.
    ++_swapGen;
    _log.debug('[engine] pause → gen=$_swapGen');
    // Глушим ОБА плеера: во время crossfade старый (`from`) ещё звучит, и
    // пауза только `_active` оставляла бы его играющим («поставил на паузу —
    // а играет»). Пауза второго плеера идемпотентна, когда он и так стоит.
    await _a.pause();
    await _b.pause();
    // Рампа могла оставить активный на промежуточной громкости — возвращаем.
    await _active.setVolume(_userVolume);
  }

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
    if (!_preloadReady) {
      _log.warning('[swap] called but preload not ready — no-op');
      return;
    }
    final gen = ++_swapGen;
    _log.debug('[swap] gen=$gen crossfade=${crossfade.inMilliseconds}ms');
    final from = _active;
    final to = _inactive;
    _preloadReady = false;

    // ИНВАРИАНТ: `_active` указывает на плеер «текущего трека» сразу, ещё до
    // окончания рампы. Тогда громкость/позиция/play-pause всегда рулят новым
    // треком, а старый просто гаснет в фоне — даже если нас прервут.
    _active = to;
    _bindActive();
    // Защита от унаследованной позиции у preload'ного плеера.
    await to.seek(Duration.zero);

    if (crossfade <= Duration.zero) {
      // Gapless: мгновенный swap.
      await to.setVolume(_userVolume);
      _play(to);
      await from.pause();
      return;
    }

    // Crossfade: оба играют, линейная рампа громкости. Фон (`from`) гаснет,
    // передний (`to` = новый `_active`) набирает до _userVolume.
    const stepMs = 50;
    final steps = (crossfade.inMilliseconds / stepMs).clamp(1, 10000).toInt();
    _log.debug(
      '[crossfade] start gen=$gen steps=$steps userVol=$_userVolume',
    );
    await to.setVolume(0);
    _play(to);
    for (var i = 1; i <= steps; i++) {
      if (gen != _swapGen) {
        _log.warning(
          '[crossfade] ABORT mid-ramp step=$i/$steps gen=$gen now=$_swapGen '
          'toVol=${_userVolume * (i / steps)}',
        );
        return; // нас перебила новая load/swap — выходим
      }
      final t = i / steps;
      await from.setVolume(_userVolume * (1 - t));
      await to.setVolume(_userVolume * t);
      await Future<void>.delayed(const Duration(milliseconds: stepMs));
    }
    if (gen != _swapGen) {
      _log.warning('[crossfade] ABORT post-loop gen=$gen now=$_swapGen');
      return;
    }
    await from.pause();
    await to.setVolume(_userVolume);
    _log.debug('[crossfade] done → to=userVol=$_userVolume');
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
  final engine = JustAudioEngine(ref.read(talkerProvider));
  ref.onDispose(engine.dispose);
  return engine;
});
