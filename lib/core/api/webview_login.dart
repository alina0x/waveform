import 'dart:async';

import 'package:desktop_webview_window/desktop_webview_window.dart';

import 'datadome_store.dart' show kSoundcloudBypassCookies;

/// Successful login result: the OAuth token + every SoundCloud cookie
/// the WebView accumulated while the user signed in. The cookie jar is
/// what powers the DataDome bypass (`adopt`-ed into [DataDomeStore]);
/// without it, mutating endpoints like `track_likes` 403 against bot
/// detection.
typedef LoginCapture = ({String? token, Map<String, String> cookies});

/// Вход через настоящую страницу логина SoundCloud в embedded WebView.
/// Пароль вводится на сайте SC — мы его не видим; после входа вытаскиваем
/// `oauth_token` из cookie сессии (poll).
///
/// Ключевой момент: SoundCloud ставит `oauth_token` ещё ДО логина (гостевой),
/// поэтому каждый кандидат проверяется через [validate] (запрос `/me`). Окно
/// закрываем только когда токен реально опознан как пользовательский.
abstract final class WebviewLogin {
  static Future<bool> available() => WebviewWindow.isWebviewAvailable();

  /// Открывает soundcloud.com в webview, чтобы пользователь прошёл проверку
  /// (капча/анти-абуз — часто всплывает под VPN при действиях вроде лайка).
  /// Завершается при закрытии окна.
  ///
  /// Возвращает SC-bypass cookies, набранные WebView'ом (datadome,
  /// sc_tracking_anonymous_id, …). Caller передаёт их в [DataDomeStore]:
  /// после успешного captcha SoundCloud ставит `datadome` cookie, и наш
  /// Dio начинает посылать его на каждом запросе.
  static Future<Map<String, String>> openVerification() async {
    if (!await available()) return const {};
    final webview = await WebviewWindow.create(
      configuration: const CreateConfiguration(
        title: 'Verify on SoundCloud',
        windowWidth: 980,
        windowHeight: 760,
      ),
    );
    webview.launch('https://soundcloud.com');
    // Read cookies WHILE the webview is open — at `onClose` the underlying
    // OS window is being torn down and `getAllCookies` returns empty on
    // some Edge builds. Poll instead: each successful read keeps the
    // freshest value, last one wins.
    final captured = <String, String>{};
    Timer? poll;
    poll = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        captured.addAll(await _readBypassCookies(webview));
      } catch (_) {
        // window closed mid-read; the awaited onClose below will finalize.
      }
    });
    await webview.onClose;
    poll.cancel();
    return Map<String, String>.unmodifiable(captured);
  }

  static Future<LoginCapture> signIn({
    required Future<bool> Function(String token) validate,
  }) async {
    final webview = await WebviewWindow.create(
      configuration: const CreateConfiguration(
        title: 'Sign in to SoundCloud',
        windowWidth: 980,
        windowHeight: 760,
      ),
    );

    final completer = Completer<String?>();
    final cookieJar = <String, String>{};
    Timer? poll;
    String? lastChecked; // не валидируем один и тот же токен повторно

    Future<void> capture() async {
      if (completer.isCompleted) return;
      try {
        final cookies = await webview.getAllCookies();
        // Harvest bypass cookies alongside the oauth_token poll — by the
        // time the user completes login, SC has handed out a blessed
        // `datadome` cookie that we want to persist for api-v2 calls.
        for (final c in cookies) {
          if (c.value.isEmpty || !c.domain.contains('soundcloud')) continue;
          if (kSoundcloudBypassCookies.contains(c.name)) {
            cookieJar[c.name] = c.value;
          }
        }

        final raw = cookies
            .where(
              (c) =>
                  c.name == 'oauth_token' &&
                  c.value.isNotEmpty &&
                  c.domain.contains('soundcloud'),
            )
            .map((c) => c.value)
            .firstOrNull;
        if (raw == null) return;

        // Cookie иногда percent-encoded — раскодируем, но без падения.
        String token = raw;
        if (raw.contains('%')) {
          try {
            token = Uri.decodeComponent(raw);
          } catch (_) {}
        }
        if (token == lastChecked) return;
        lastChecked = token;

        // Гостевой/просроченный токен не пройдёт /me — ждём настоящего входа.
        if (!await validate(token)) return;
        if (completer.isCompleted) return;
        completer.complete(token);
        poll?.cancel();
        webview.close();
      } catch (_) {
        // окно могло закрыться между проверками — игнорируем
      }
    }

    webview.setOnUrlRequestCallback((url) {
      capture();
      return true;
    });
    poll = Timer.periodic(const Duration(seconds: 2), (_) => capture());
    webview.onClose.then((_) {
      poll?.cancel();
      if (!completer.isCompleted) completer.complete(null);
    });

    webview.launch('https://soundcloud.com/signin');
    final token = await completer.future;
    return (token: token, cookies: Map<String, String>.unmodifiable(cookieJar));
  }

  /// Reads any SC bypass cookie the WebView currently knows about. Empty
  /// when the webview is closed or has no soundcloud cookies yet.
  static Future<Map<String, String>> _readBypassCookies(Webview wv) async {
    final out = <String, String>{};
    final cookies = await wv.getAllCookies();
    for (final c in cookies) {
      if (c.value.isEmpty || !c.domain.contains('soundcloud')) continue;
      if (kSoundcloudBypassCookies.contains(c.name)) {
        out[c.name] = c.value;
      }
    }
    return out;
  }
}
