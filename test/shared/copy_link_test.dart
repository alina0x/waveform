import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waveform_app/core/deeplinks/clipboard_watcher.dart';
import 'package:waveform_app/shared/url_share.dart';

void main() {
  // Mock the Clipboard platform channel so Clipboard.setData doesn't block.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Provide a no-op clipboard handler.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (MethodCall call) async {
            if (call.method == 'Clipboard.setData') return null;
            if (call.method == 'Clipboard.getData') return null;
            return null;
          },
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('copyToClipboard with ref marks the url as already-seen',
      (tester) async {
    String? seen;
    late Future<void> Function() triggerCopy;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clipboardWatcherProvider.overrideWith(
            (ref) => _SpyWatcher((u) => seen = u),
          ),
        ],
        child: MaterialApp(
          home: Consumer(builder: (context, ref, _) {
            triggerCopy = () => copyToClipboard(
              context,
              'https://soundcloud.com/x/y',
              ref: ref,
            );
            return TextButton(
              onPressed: () => triggerCopy(),
              child: const Text('copy'),
            );
          }),
        ),
      ),
    );

    // Prime Consumer build.
    await tester.pump();
    // Call directly and await the whole async chain.
    await triggerCopy();
    // markSeen is called before showToast; assert immediately.
    expect(seen, 'https://soundcloud.com/x/y');
    // Drain the 4-second Future.delayed timer created by showToast so the
    // test framework's pending-timer check doesn't fire.
    await tester.pump(const Duration(seconds: 5));
  });
}

class _SpyWatcher implements ClipboardWatcher {
  _SpyWatcher(this._onMarkSeen);
  final void Function(String) _onMarkSeen;

  @override
  void markSeen(String url) => _onMarkSeen(url);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
