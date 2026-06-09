import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waveform_app/app/shortcut_bindings.dart';
import 'package:waveform_app/shared/intents.dart';

// SingleActivator does not override == so we can't use map[const SingleActivator(...)].
// Instead, look up entries by scanning the map for matching activators via
// the ShortcutActivator.triggers property.
Intent? _find(Map<ShortcutActivator, Intent> m, LogicalKeyboardKey key,
    {bool shift = false, bool meta = false, bool control = false}) {
  for (final entry in m.entries) {
    final a = entry.key;
    if (a is SingleActivator &&
        a.trigger == key &&
        a.shift == shift &&
        a.meta == meta &&
        a.control == control) {
      return entry.value;
    }
  }
  return null;
}

void main() {
  test('bare arrows seek, shift-arrows change track, shift-vert volume', () {
    final m = buildShortcuts(isMac: true, location: '/');
    expect(_find(m, LogicalKeyboardKey.arrowRight), isA<SeekForwardIntent>());
    expect(_find(m, LogicalKeyboardKey.arrowLeft), isA<SeekBackwardIntent>());
    expect(_find(m, LogicalKeyboardKey.arrowRight, shift: true), isA<NextTrackIntent>());
    expect(_find(m, LogicalKeyboardKey.arrowLeft, shift: true), isA<PrevTrackIntent>());
    expect(_find(m, LogicalKeyboardKey.arrowUp, shift: true), isA<VolumeUpIntent>());
    expect(_find(m, LogicalKeyboardKey.arrowDown, shift: true), isA<VolumeDownIntent>());
  });

  test('single letters and digits map to web-parity intents', () {
    final m = buildShortcuts(isMac: true, location: '/');
    expect(_find(m, LogicalKeyboardKey.keyL), isA<LikePlayingIntent>());
    expect(_find(m, LogicalKeyboardKey.keyL, shift: true), isA<RepeatToggleIntent>());
    expect(_find(m, LogicalKeyboardKey.keyR), isA<RepostPlayingIntent>());
    expect(_find(m, LogicalKeyboardKey.keyM), isA<MuteToggleIntent>());
    expect(_find(m, LogicalKeyboardKey.keyS), isA<OpenSearchIntent>());
    expect(_find(m, LogicalKeyboardKey.keyS, shift: true), isA<ShuffleToggleIntent>());
    expect(_find(m, LogicalKeyboardKey.keyP), isA<NavigateToPlayingIntent>());
    expect(_find(m, LogicalKeyboardKey.keyQ), isA<ToggleQueueIntent>());
    expect(_find(m, LogicalKeyboardKey.keyH), isA<ShowShortcutsIntent>());
    expect(_find(m, LogicalKeyboardKey.digit3), isA<SeekToPercentIntent>());
  });
}
