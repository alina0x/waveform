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
