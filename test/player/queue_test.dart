import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waveform_app/core/api/liked_tracks.dart';
import 'package:waveform_app/core/audio/audio_engine.dart';
import 'package:waveform_app/features/player/player_controller.dart';
import 'package:waveform_app/shared/models/track.dart';

import '../support/fake_audio_engine.dart';
import '../support/stub_liked_tracks.dart';

Track t(String id) => Track(
  id: id,
  title: 'T$id',
  artist: 'A',
  durationMs: 100000,
  likes: 0,
  reposts: 0,
  plays: 0,
  waveform: const <double>[],
);

ProviderContainer harness(FakeAudioEngine engine) => ProviderContainer(
  overrides: [
    audioEngineProvider.overrideWithValue(engine),
    likedTracksProvider.overrideWith(StubLikedTracks.new),
  ],
);

void main() {
  test(
    'harness builds the controller and play() sets current without network',
    () {
      final engine = FakeAudioEngine();
      final c = harness(engine);
      addTearDown(c.dispose);
      final pc = c.read(playerControllerProvider.notifier);
      pc.play(t('1'), queue: [t('1'), t('2'), t('3')]);
      expect(c.read(playerControllerProvider).track?.id, '1');
      expect(pc.upcomingTracks.map((x) => x.id), ['2', '3']);
    },
  );
}
