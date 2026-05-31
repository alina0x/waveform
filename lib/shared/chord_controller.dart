import 'dart:async';

import 'package:flutter/services.dart';

/// Назначения для `G`-then-key (по аналогии с web SoundCloud).
enum ChordTarget { likes, feed, library, profile, history }

/// Маленький автомат для аккорда `G` затем клавиша. `arm()` открывает окно;
/// следующая подходящая клавиша → цель и разоружение, иначе/таймаут → отмена.
class ChordController {
  ChordController({this.window = const Duration(milliseconds: 1200)});

  final Duration window;
  Timer? _timer;
  bool _armed = false;

  bool get armed => _armed;

  void arm() {
    _armed = true;
    _timer?.cancel();
    _timer = Timer(window, disarm);
  }

  void disarm() {
    _armed = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Если заряжён — отдаёт цель для клавиши (или null для несовпадения) и
  /// разоружается. Если не заряжён — null.
  ChordTarget? resolve(LogicalKeyboardKey key) {
    if (!_armed) return null;
    disarm();
    if (key == LogicalKeyboardKey.keyL) return ChordTarget.likes;
    if (key == LogicalKeyboardKey.keyS) return ChordTarget.feed;
    if (key == LogicalKeyboardKey.keyC) return ChordTarget.library;
    if (key == LogicalKeyboardKey.keyP) return ChordTarget.profile;
    if (key == LogicalKeyboardKey.keyH) return ChordTarget.history;
    return null;
  }

  void dispose() => _timer?.cancel();
}
