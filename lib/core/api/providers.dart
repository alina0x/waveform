import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talker_dio_logger/talker_dio_logger.dart';

import '../log/talker.dart';
import 'client_id_resolver.dart';
import 'http_soundcloud_api.dart';
import 'mock_soundcloud_api.dart';
import 'soundcloud_api.dart';
import 'soundcloud_auth.dart';

final _dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );
  // Логируем все запросы/ответы/ошибки api-v2. Заголовки НЕ печатаем —
  // чтобы не светить OAuth-токен в логах.
  dio.interceptors.add(
    TalkerDioLogger(
      talker: ref.watch(talkerProvider),
      settings: const TalkerDioLoggerSettings(
        // Тела ответов api-v2 огромны (списки треков) — НЕ логируем их целиком,
        // иначе история раздувается до мегабайт. Достаточно строки запроса +
        // статуса; для ошибок оставляем тело (оно короткое и полезно).
        printRequestHeaders: false,
        printResponseHeaders: false,
        printRequestData: false,
        printResponseData: false,
        printResponseMessage: false,
        printErrorData: true,
        printErrorMessage: true,
      ),
    ),
  );
  return dio;
});

final _clientIdResolverProvider = Provider<ClientIdResolver>(
  (ref) => ClientIdResolver(ref.read(_dioProvider)),
);

/// Единая точка доступа к API. По умолчанию — живой api-v2 (client_id + OAuth):
/// приложение показывает реальные данные SoundCloud, без моков.
/// Сборка с `--dart-define=MOCK=true` поднимает моки (offline-разработка);
/// тесты переопределяют провайдер напрямую через [MockSoundcloudApi].
final soundcloudApiProvider = Provider<SoundcloudApi>((ref) {
  const mock = bool.fromEnvironment('MOCK');
  if (mock) return const MockSoundcloudApi();
  return HttpSoundcloudApi(
    ref.watch(_dioProvider),
    ref.watch(_clientIdResolverProvider),
    auth: ref.watch(authControllerProvider),
    talker: ref.watch(talkerProvider),
  );
});
