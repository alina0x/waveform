import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:talker_riverpod_logger/talker_riverpod_logger.dart';

import 'app/app.dart';
import 'core/log/talker.dart';

void main() {
  // Единый Talker: им же логируются Dio-запросы и Riverpod-события.
  // Ограничиваем историю — иначе память/экспорт логов растут безгранично.
  final talker = TalkerFlutter.init(
    settings: TalkerSettings(maxHistoryItems: 1000),
  );
  runApp(
    ProviderScope(
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
      child: const WaveformApp(),
    ),
  );
}
