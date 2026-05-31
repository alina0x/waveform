import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waveform_app/features/shortcuts/shortcuts_overlay.dart';

void main() {
  testWidgets('overlay open provider toggles and lists shortcuts', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(shortcutsOverlayOpenProvider), isFalse);
    container.read(shortcutsOverlayOpenProvider.notifier).open();
    expect(container.read(shortcutsOverlayOpenProvider), isTrue);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: ShortcutsOverlay())),
      ),
    );
    await tester.pump();
    expect(find.text('Keyboard shortcuts'), findsOneWidget);
    expect(find.textContaining('seek'), findsWidgets);
  });
}
