import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:waveform_app/core/audio/audio_engine.dart';

/// Подделка just_audio [AudioPlayer], моделирующая ключевое поведение, из-за
/// которого жил баг «тихий входящий трек при crossfade»: `play()` возвращает
/// future, которая НЕ завершается, пока воспроизведение не остановят (ровно
/// как настоящий just_audio во время игры). Если движок `await`'ит этот
/// `play()` до рампы громкости — рампа не выполнится и тест зависнет.
class _FakePlayer implements AudioPlayer {
  final _state = StreamController<ProcessingState>.broadcast();
  final _pos = StreamController<Duration>.broadcast();
  final _buf = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();

  /// Future от play() — намеренно никогда не завершается.
  final Completer<void> playCompleter = Completer<void>();
  final List<double> volumes = [];
  bool played = false;

  double? get lastVolume => volumes.isEmpty ? null : volumes.last;

  @override
  Stream<ProcessingState> get processingStateStream => _state.stream;
  @override
  Stream<Duration> get positionStream => _pos.stream;
  @override
  Stream<Duration> get bufferedPositionStream => _buf.stream;
  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  dynamic noSuchMethod(Invocation inv) {
    switch (inv.memberName) {
      case #setVolume:
        volumes.add(inv.positionalArguments.first as double);
        return Future<void>.value();
      case #play:
        played = true;
        return playCompleter.future; // никогда не завершается
      case #setUrl:
        return Future<Duration?>.value(const Duration(seconds: 1));
      case #seek:
      case #pause:
      case #stop:
      case #dispose:
        return Future<void>.value();
      default:
        return null;
    }
  }
}

void main() {
  final talker = TalkerFlutter.init();

  test(
    'crossfade swap ramps incoming player to full volume and returns '
    '(does not await the blocking play() future)',
    () async {
      final players = <_FakePlayer>[];
      final engine = JustAudioEngine(
        talker,
        createPlayer: () {
          final p = _FakePlayer();
          players.add(p);
          return p;
        },
      );

      await engine.preloadNext('next-url');
      expect(engine.hasPreload, isTrue);

      // До фикса здесь висел `await to.play()` (future preload'ного плеера не
      // завершается) → swapToNext не возвращается → timeout = провал теста.
      await engine
          .swapToNext(crossfade: const Duration(milliseconds: 100))
          .timeout(const Duration(seconds: 2));

      final incoming = players[1]; // _b стал активным `to`
      expect(incoming.played, isTrue);
      // Рампа дошла до конца → входящий выходит на пользовательскую громкость
      // (по умолчанию 1.0), а НЕ застывает у нуля.
      expect(incoming.lastVolume, closeTo(1.0, 1e-9));

      engine.dispose();
    },
  );

  test('gapless swap returns promptly and brings incoming to full volume',
      () async {
    final players = <_FakePlayer>[];
    final engine = JustAudioEngine(
      talker,
      createPlayer: () {
        final p = _FakePlayer();
        players.add(p);
        return p;
      },
    );

    await engine.preloadNext('next-url');
    await engine.swapToNext().timeout(const Duration(seconds: 2));

    expect(players[1].played, isTrue);
    expect(players[1].lastVolume, closeTo(1.0, 1e-9));

    engine.dispose();
  });

  test('load() does not block on play()', () async {
    final engine = JustAudioEngine(talker, createPlayer: _FakePlayer.new);
    await engine.load('url').timeout(const Duration(seconds: 2));
    engine.dispose();
  });
}
