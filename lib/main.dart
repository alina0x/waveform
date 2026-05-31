import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:media_kit/media_kit.dart' show MPVLogLevel;
import 'package:talker_flutter/talker_flutter.dart';
import 'package:talker_riverpod_logger/talker_riverpod_logger.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'core/audio/waveform_audio_handler.dart';
import 'core/log/talker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // just_audio has no native Windows/Linux backend; without this every
  // setUrl() throws MissingPluginException and the PlayerController auto-
  // skips every track. JustAudioMediaKit registers a libmpv-backed
  // platform implementation so MP3/HLS/AAC all play on desktop. No-op on
  // mobile/macOS where the bundled platform plugin is used.
  if (Platform.isWindows || Platform.isLinux) {
    // Raise libmpv log level BEFORE ensureInitialized — the field is read at
    // player construction. `warn` surfaces broken HLS playlists, missing
    // codecs, and audio-output failures (default `error` swallowed most of
    // them, leaving us blind to "play does nothing" on Windows).
    JustAudioMediaKit.mpvLogLevel = MPVLogLevel.warn;
    JustAudioMediaKit.ensureInitialized(windows: true, linux: true);
  }

  // Window manager — для динамического title и базового sizing на desktop.
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await windowManager.ensureInitialized();
    const opts = WindowOptions(
      title: 'Waveform',
      minimumSize: Size(960, 640),
      titleBarStyle: TitleBarStyle.hidden,
    );
    // waitUntilReadyToShow гарантирует, что окно создано до setTitle.
    await windowManager.waitUntilReadyToShow(opts, () async {
      await windowManager.setTitle('Waveform');
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // Единый Talker: им же логируются Dio-запросы и Riverpod-события.
  final talker = TalkerFlutter.init(
    settings: TalkerSettings(maxHistoryItems: 1000),
  );

  // Bridge `package:logging` → Talker. media_kit and our JustAudioEngine emit
  // through `Logger`; without this bridge those records vanish into stderr
  // (and on Windows `flutter run --release` swallows stderr entirely).
  // Anything WARNING or above → talker.warning so it shows in /logs.
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((rec) {
    final tag = '[${rec.loggerName}] ${rec.message}';
    if (rec.level >= Level.SEVERE) {
      talker.error(tag, rec.error, rec.stackTrace);
    } else if (rec.level >= Level.WARNING) {
      talker.warning(tag, rec.error, rec.stackTrace);
    } else if (rec.level >= Level.INFO) {
      talker.info(tag);
    } else {
      talker.debug(tag);
    }
  });

  // 1) Поднимаем audio_service. Handler создаётся ДО ProviderContainer'а —
  //    у него ещё нет ссылки на container; назначим её ниже. Методы handler'а
  //    (play/pause/...) дёргаются только когда пользователь жмёт media-keys —
  //    к тому моменту container уже привязан.
  //
  //    Windows: audio_service не имеет нативного плагина (см. .flutter-plugins-
  //    dependencies). `AudioService.init` ставит default-platform-interface,
  //    который на Windows тихо отвечает no-op'ом — но при этом всё равно
  //    пытается завести isolate + StreamHandler, что несколько раз приводило
  //    к «зависанию плагин-канала на старте». Просто создаём handler напрямую:
  //    его `mediaItem`/`playbackState` — BehaviorSubject'ы, они работают без
  //    init. SMTC-интеграция (медиа-клавиши, lockscreen now-playing на Win)
  //    — отдельный TODO, нужен либо flutter_smtc, либо нативный плагин.
  final WaveformAudioHandler handler;
  if (Platform.isWindows) {
    handler = WaveformAudioHandler();
  } else {
    handler = await AudioService.init(
      builder: () => WaveformAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.waveform.player',
        androidNotificationChannelName: 'Waveform',
        androidNotificationOngoing: true,
      ),
    );
  }
  setAudioHandlerSingleton(handler);

  // 2) Создаём ProviderContainer с overrides — отсюда же его поднимет
  //    UncontrolledProviderScope.
  final container = ProviderContainer(
    observers: [
      TalkerRiverpodObserver(
        talker: talker,
        settings: const TalkerRiverpodLoggerSettings(
          printProviderAdded: true,
          printProviderUpdated: false, // плеер тикает позицией — был бы флуд
          printProviderDisposed: false,
          printProviderFailed: true,
        ),
      ),
    ],
    overrides: [talkerProvider.overrideWithValue(talker)],
  );
  handler.container = container;

  runApp(
    UncontrolledProviderScope(container: container, child: const WaveformApp()),
  );
}
