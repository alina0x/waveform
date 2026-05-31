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
}
