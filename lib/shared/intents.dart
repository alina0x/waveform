import 'package:flutter/widgets.dart';

/// Глобальные Intent'ы для биндинга `Shortcuts` + `Actions` в AppShell.
/// CallbackAction'ы определяются в одном месте (AppShell.build), так что
/// все клавиатурные сокращения идут через один граф `Actions`.

class PlayPauseIntent extends Intent {
  const PlayPauseIntent();
}

class NextTrackIntent extends Intent {
  const NextTrackIntent();
}

class PrevTrackIntent extends Intent {
  const PrevTrackIntent();
}

class FocusOmniboxIntent extends Intent {
  const FocusOmniboxIntent();
}

class JumpLikesIntent extends Intent {
  const JumpLikesIntent();
}

class JumpSettingsIntent extends Intent {
  const JumpSettingsIntent();
}

class JumpLogsIntent extends Intent {
  const JumpLogsIntent();
}

class VolumeUpIntent extends Intent {
  const VolumeUpIntent();
}

class VolumeDownIntent extends Intent {
  const VolumeDownIntent();
}

/// Enter на `/track/:id` — играть/возобновить трек этой страницы.
/// Биндинг добавляется в `_shortcuts()` только когда route matches.
class PlayPageTrackIntent extends Intent {
  const PlayPageTrackIntent();
}

class SeekForwardIntent extends Intent {
  const SeekForwardIntent();
}

class SeekBackwardIntent extends Intent {
  const SeekBackwardIntent();
}

class LikePlayingIntent extends Intent {
  const LikePlayingIntent();
}

class RepeatToggleIntent extends Intent {
  const RepeatToggleIntent();
}

class RepostPlayingIntent extends Intent {
  const RepostPlayingIntent();
}

class MuteToggleIntent extends Intent {
  const MuteToggleIntent();
}

class ShuffleToggleIntent extends Intent {
  const ShuffleToggleIntent();
}

class NavigateToPlayingIntent extends Intent {
  const NavigateToPlayingIntent();
}

class OpenSearchIntent extends Intent {
  const OpenSearchIntent();
}

class ToggleQueueIntent extends Intent {
  const ToggleQueueIntent();
}

class ShowShortcutsIntent extends Intent {
  const ShowShortcutsIntent();
}

class CopyLinkIntent extends Intent {
  const CopyLinkIntent();
}

/// Seek к проценту позиции (0 = начало … 9 = 90%).
class SeekToPercentIntent extends Intent {
  const SeekToPercentIntent(this.tenth);
  final int tenth; // 0..9
}
