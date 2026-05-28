import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:talker_flutter/talker_flutter.dart';
import 'package:waveform_app/app/app.dart';
import 'package:waveform_app/app/router.dart';
import 'package:waveform_app/core/api/mock_soundcloud_api.dart';
import 'package:waveform_app/core/api/providers.dart';
import 'package:waveform_app/core/api/soundcloud_auth.dart';
import 'package:waveform_app/core/audio/audio_engine.dart';
import 'package:waveform_app/core/log/talker.dart';
import 'package:waveform_app/features/home/mock_tracks.dart';

/// Заглушка звукового движка — без плагина just_audio в тестах.
class _FakeAudioEngine implements AudioEngine {
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<Duration> get bufferedPositionStream => const Stream.empty();
  @override
  Stream<bool> get playingStream => const Stream.empty();
  @override
  Stream<void> get completedStream => const Stream.empty();
  @override
  Future<void> load(String url) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> stop() async {}
  @override
  void dispose() {}
}

void main() {
  // Десктопный вьюпорт — приложение рассчитано на широкое окно.
  void useDesktopViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  // Данные async (FutureProvider + задержка мока). Спиннер крутится бесконечно,
  // поэтому ждём фикс. длительностью, а не pumpAndSettle.
  Future<void> load(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
  }

  Future<ProviderContainer> pumpApp(WidgetTester tester,
      {bool loggedIn = false}) async {
    useDesktopViewport(tester);
    // Приложение по умолчанию ходит в живой api-v2 — в тестах подменяем моком.
    await tester.pumpWidget(ProviderScope(
      overrides: [
        soundcloudApiProvider.overrideWithValue(const MockSoundcloudApi()),
        audioEngineProvider.overrideWithValue(_FakeAudioEngine()),
        talkerProvider.overrideWithValue(Talker()),
      ],
      child: const WaveformApp(),
    ));
    appRouter.go('/'); // appRouter глобальный — сбрасываем навигацию между тестами
    await tester.pump();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(WaveformApp)));
    if (loggedIn) {
      container.read(authControllerProvider.notifier).signIn('2-test-token');
    }
    await load(tester);
    return container;
  }

  testWidgets('Home shows curated shelves, hides personal stream when anon',
      (tester) async {
    await pumpApp(tester);

    expect(find.text('waveform'), findsOneWidget);
    expect(find.text('from your stream'), findsNothing); // аноним
    expect(find.text('select a track'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('mixed for you'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('mixed for you'), findsOneWidget);
  });

  testWidgets('Tapping a track card starts playback', (tester) async {
    // Залогинен → видно «from your stream» с играбельными карточками треков.
    await pumpApp(tester, loggedIn: true);

    await tester.tap(find.byIcon(Icons.play_arrow).first);
    await tester.pump();

    expect(find.text('select a track'), findsNothing);
    expect(find.byIcon(Icons.pause), findsWidgets);
  });

  testWidgets('Personal "from your stream" shows when logged in',
      (tester) async {
    await pumpApp(tester, loggedIn: true);
    expect(find.text('from your stream'), findsOneWidget);
    expect(find.text(mockTracks.first.title), findsWidgets);
  });

  testWidgets('Tapping a track title opens the track screen', (tester) async {
    await pumpApp(tester, loggedIn: true);

    await tester.tap(find.text(mockTracks.first.title).first);
    await load(tester);

    expect(find.text('#ambient techno'), findsOneWidget);
    expect(find.text('related tracks'), findsOneWidget);
  });

  testWidgets('Tapping an artist opens the artist screen', (tester) async {
    await pumpApp(tester, loggedIn: true);

    await tester.tap(find.text(mockTracks.first.artist).first);
    await load(tester);

    expect(find.text('popular tracks'), findsOneWidget);
    expect(find.text('followers'), findsOneWidget);
  });

  testWidgets('Feed is gated behind login when anon', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('feed'));
    await load(tester);

    expect(find.text('your feed'), findsOneWidget);
    expect(find.text('this is your feed'), findsNothing);
  });

  testWidgets('Library is gated behind login when anon', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('library'));
    await load(tester);

    expect(find.text('your library'), findsOneWidget);
  });

  testWidgets('Login/logout toggles the account UI', (tester) async {
    final container = await pumpApp(tester);
    expect(find.text('log in'), findsOneWidget);

    container.read(authControllerProvider.notifier).signIn('2-test-token');
    await tester.pump();
    expect(find.text('log in'), findsNothing);
    expect(container.read(authControllerProvider).isAuthenticated, isTrue);

    container.read(authControllerProvider.notifier).signOut();
    await tester.pump();
    expect(container.read(authControllerProvider).isAuthenticated, isFalse);
    expect(find.text('log in'), findsWidgets); // account-кнопка вернулась
  });
}
