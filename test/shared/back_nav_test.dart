import 'package:flutter_test/flutter_test.dart';
import 'package:waveform_app/shared/back_nav.dart';

void main() {
  test('back gesture fires only from left edge, rightward, past threshold, when poppable', () {
    expect(shouldPopOnSwipe(canPop: true, startDx: 20, totalDx: 90), isTrue);
    expect(shouldPopOnSwipe(canPop: false, startDx: 20, totalDx: 90), isFalse);
    expect(shouldPopOnSwipe(canPop: true, startDx: 200, totalDx: 90), isFalse);
    expect(shouldPopOnSwipe(canPop: true, startDx: 20, totalDx: 30), isFalse);
    expect(shouldPopOnSwipe(canPop: true, startDx: 20, totalDx: -90), isFalse);
  });
}
