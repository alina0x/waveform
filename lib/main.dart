import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:talker_riverpod_logger/talker_riverpod_logger.dart';

import 'app/app.dart';
import 'core/audio/waveform_audio_handler.dart';
import 'core/log/talker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Единый Talker: им же логируются Dio-запросы и Riverpod-события.
  final talker = TalkerFlutter.init(
    settings: TalkerSettings(maxHistoryItems: 1000),
  );

  // 1) Поднимаем audio_service. Handler создаётся ДО ProviderContainer'а —
  //    у него ещё нет ссылки на container; назначим её ниже. Методы handler'а
  //    (play/pause/...) дёргаются только когда пользователь жмёт media-keys —
  //    к тому моменту container уже привязан.
  final handler = await AudioService.init(
    builder: () => WaveformAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.waveform.player',
      androidNotificationChannelName: 'Waveform',
      androidNotificationOngoing: true,
    ),
  );
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

  runApp(UncontrolledProviderScope(
    container: container,
    child: const WaveformApp(),
  ));
}
