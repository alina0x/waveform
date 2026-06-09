import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waveform_app/shared/chord_controller.dart';

void main() {
  test('arming G then a destination key resolves the target', () {
    final c = ChordController();
    expect(c.armed, isFalse);
    c.arm();
    expect(c.armed, isTrue);
    expect(c.resolve(LogicalKeyboardKey.keyL), ChordTarget.likes);
    expect(c.armed, isFalse); // resolving disarms
  });

  test('non-destination key while armed cancels and returns null', () {
    final c = ChordController();
    c.arm();
    expect(c.resolve(LogicalKeyboardKey.keyZ), isNull);
    expect(c.armed, isFalse);
  });

  test('arm window expires after timeout', () {
    fakeAsync((async) {
      final c = ChordController(window: const Duration(milliseconds: 1200));
      c.arm();
      async.elapse(const Duration(milliseconds: 1300));
      expect(c.armed, isFalse);
      expect(c.resolve(LogicalKeyboardKey.keyL), isNull); // not armed → no nav
    });
  });

  test('all chord targets resolve from their keys', () {
    final pairs = {
      LogicalKeyboardKey.keyL: ChordTarget.likes,
      LogicalKeyboardKey.keyS: ChordTarget.feed,
      LogicalKeyboardKey.keyC: ChordTarget.library,
      LogicalKeyboardKey.keyP: ChordTarget.profile,
      LogicalKeyboardKey.keyH: ChordTarget.history,
    };
    pairs.forEach((key, target) {
      final c = ChordController();
      c.arm();
      expect(c.resolve(key), target, reason: '$key should map to $target');
    });
  });

  test('re-arming within the window restarts the timeout', () {
    fakeAsync((async) {
      final c = ChordController(window: const Duration(milliseconds: 1200));
      c.arm();
      async.elapse(const Duration(milliseconds: 800));
      expect(c.armed, isTrue);
      c.arm(); // re-arm resets the window
      async.elapse(const Duration(milliseconds: 800)); // 1600ms since first arm, 800 since re-arm
      expect(c.armed, isTrue); // still armed because re-arm restarted the timer
      async.elapse(const Duration(milliseconds: 500)); // now 1300ms since re-arm
      expect(c.armed, isFalse);
    });
  });
}
