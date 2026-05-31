import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talker_dio_logger/talker_dio_logger.dart';

import '../log/talker.dart';
import 'client_id_resolver.dart';
import 'datadome_store.dart';
import 'http_soundcloud_api.dart';
import 'mock_soundcloud_api.dart';
import 'soundcloud_api.dart';
import 'soundcloud_auth.dart';

/// SoundCloud's web app sends a Chrome User-Agent. DataDome's blessed
/// `datadome` cookie is typically pinned to the UA family it was issued
/// to — a Dart-default UA invalidates the cookie even when present.
const _kChromeUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

/// Browser-style request headers attached to every `*.soundcloud.com`
/// call. DataDome cross-references these against the cookie's fingerprint;
/// without them the request looks like a scripted client even when the
/// cookie is valid.
const Map<String, String> _kBrowserHeaders = {
  'Accept': 'application/json, text/javascript, */*; q=0.01',
  'Accept-Language': 'en-US,en;q=0.9',
  'Origin': 'https://soundcloud.com',
  'Referer': 'https://soundcloud.com/',
  'Sec-Fetch-Site': 'same-site',
  'Sec-Fetch-Mode': 'cors',
  'Sec-Fetch-Dest': 'empty',
  'sec-ch-ua':
      '"Chromium";v="131", "Google Chrome";v="131", "Not.A/Brand";v="24"',
  'sec-ch-ua-mobile': '?0',
  'sec-ch-ua-platform': '"Windows"',
};

bool _isSoundcloudHost(String host) =>
    host.endsWith('.soundcloud.com') || host == 'soundcloud.com';

bool _isDataDomeBlock(DioException e) {
  final res = e.response;
  if (res == null || res.statusCode != 403) return false;
  // DataDome stamps every blocked response with `x-datadome: protected`
  // or `x-dd-b: 1`; the JSON body also carries a `captcha-delivery.com`
  // URL but headers are cheaper to read.
  return res.headers.value('x-datadome') == 'protected' ||
      res.headers.value('x-dd-b') == '1';
}

void _applyBypass(RequestOptions options, String? cookieHeader) {
  if (!_isSoundcloudHost(options.uri.host)) return;
  _kBrowserHeaders.forEach((k, v) {
    // Don't clobber a header the caller explicitly set (e.g. Authorization
    // is *not* in this map but the existing logic relies on header maps
    // never being silently overwritten).
    options.headers.putIfAbsent(k, () => v);
  });
  if (cookieHeader == null || cookieHeader.isEmpty) return;
  final existing = options.headers['Cookie'] ?? options.headers['cookie'];
  options.headers['Cookie'] = existing is String && existing.isNotEmpty
      ? '$existing; $cookieHeader'
      : cookieHeader;
}

final _dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      // See [_kChromeUserAgent] — required for the DataDome cookie to
      // remain valid. Per-host overrides not needed: every endpoint we
      // call is soundcloud.com.
      headers: {'User-Agent': _kChromeUserAgent},
    ),
  );

  // DataDome bypass: attach the cached cookie jar on every SC request;
  // on a 403-DataDome block, refresh from disk + Chromium and retry the
  // original request once.
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        _applyBypass(options, ref.read(dataDomeProvider));
        handler.next(options);
      },
      onError: (e, handler) async {
        final retried = e.requestOptions.extra['_dd_retried'] == true;
        if (retried || !_isDataDomeBlock(e)) {
          handler.next(e);
          return;
        }
        final log = ref.read(talkerProvider);
        log.warning(
          'datadome: ${e.requestOptions.method} ${e.requestOptions.path} '
          'blocked, refreshing cookie + retrying',
        );
        final stale = ref.read(dataDomeProvider);
        await ref.read(dataDomeProvider.notifier).refresh();
        final fresh = ref.read(dataDomeProvider);
        // No point retrying if we couldn't load anything new — the same
        // cookie that just failed would only fail again. Surface the
        // original 403 to the caller (LikeOutcome.blocked toast).
        if (fresh == null || fresh.isEmpty || fresh == stale) {
          handler.next(e);
          return;
        }
        final retryOptions = e.requestOptions.copyWith(
          extra: {...e.requestOptions.extra, '_dd_retried': true},
        );
        // Strip the stale Cookie line so onRequest's re-run attaches
        // the freshly-loaded jar cleanly instead of appending it next
        // to the prior value.
        retryOptions.headers.remove('Cookie');
        retryOptions.headers.remove('cookie');
        try {
          final response = await dio.fetch<dynamic>(retryOptions);
          handler.resolve(response);
        } on DioException catch (e2) {
          handler.next(e2);
        }
      },
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
