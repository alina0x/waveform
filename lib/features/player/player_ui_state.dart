import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Свёрнут ли BottomPlayer. Collapsed = 44px только с базовыми контролами;
/// expanded = полный плеер с waveform/volume (AppTheme.playerHeight).
/// Хочется со временем персистить — пока в памяти.
class PlayerCollapsedController extends Notifier<bool> {
  @override
  bool build() => false;
  void toggle() => state = !state;
  void collapse() => state = true;
  void expand() => state = false;
}

final playerCollapsedProvider =
    NotifierProvider<PlayerCollapsedController, bool>(
        PlayerCollapsedController.new);
