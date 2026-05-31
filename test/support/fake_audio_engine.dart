import 'dart:async';

import 'package:waveform_app/core/audio/audio_engine.dart';

/// Заглушка движка для тестов PlayerController. Стримы — broadcast, ничего не
/// эмитят сами; методы записывают последний вызов.
class FakeAudioEngine implements AudioEngine {
  final _position = StreamController<Duration>.broadcast();
  final _buffered = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _completed = StreamController<void>.broadcast();

  Duration? lastSeek;
  double? lastVolume;
  String? lastLoadedUrl;

  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<Duration> get bufferedPositionStream => _buffered.stream;
  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<void> get completedStream => _completed.stream;

  @override
  Future<void> load(String url) async => lastLoadedUrl = url;
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> seek(Duration position) async => lastSeek = position;
  @override
  Future<void> setVolume(double volume) async => lastVolume = volume;
  @override
  Future<void> stop() async {}
  @override
  Future<void> preloadNext(String? url) async {}
  @override
  Future<void> swapToNext({Duration crossfade = Duration.zero}) async {}
  @override
  bool get hasPreload => false;
  @override
  void dispose() {
    _position.close();
    _buffered.close();
    _playing.close();
    _completed.close();
  }
}
