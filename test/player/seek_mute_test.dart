import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waveform_app/core/api/liked_tracks.dart';
import 'package:waveform_app/core/audio/audio_engine.dart';
import 'package:waveform_app/features/player/player_controller.dart';
import 'package:waveform_app/shared/models/track.dart';

import '../support/fake_audio_engine.dart';
import '../support/stub_liked_tracks.dart';

Track t(String id, {int durMs = 100000}) => Track(
  id: id, title: 'T', artist: 'A', durationMs: durMs,
  likes: 0, reposts: 0, plays: 0, waveform: const <double>[],
);

ProviderContainer harness(FakeAudioEngine e) => ProviderContainer(overrides: [
  audioEngineProvider.overrideWithValue(e),
  likedTracksProvider.overrideWith(StubLikedTracks.new),
]);

void main() {
  test('seekBy adds delta and clamps to [0, duration]', () {
    final e = FakeAudioEngine();
    final c = harness(e);
    addTearDown(c.dispose);
    final pc = c.read(playerControllerProvider.notifier);
    pc.play(t('1', durMs: 100000)); // 100s
    pc.seekBy(const Duration(seconds: 5));
    expect(e.lastSeek, const Duration(seconds: 5));
    pc.seekBy(const Duration(seconds: -100)); // clamps to 0
    expect(e.lastSeek, Duration.zero);
    pc.seekBy(const Duration(seconds: 9999)); // clamps to duration
    expect(e.lastSeek, const Duration(milliseconds: 100000));
  });

  test('toggleMute zeroes engine volume then restores it', () {
    final e = FakeAudioEngine();
    final c = harness(e);
    addTearDown(c.dispose);
    final pc = c.read(playerControllerProvider.notifier);
    pc.play(t('1'));
    pc.setVolume(0.5);
    expect(c.read(playerControllerProvider).muted, isFalse);
    pc.toggleMute();
    expect(c.read(playerControllerProvider).muted, isTrue);
    expect(e.lastVolume, 0.0);
    pc.toggleMute();
    expect(c.read(playerControllerProvider).muted, isFalse);
    expect(e.lastVolume, closeTo(0.5 * 0.5 * 0.5, 1e-9)); // perceptual cube
  });
}
