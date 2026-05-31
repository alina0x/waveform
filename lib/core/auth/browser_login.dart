import 'dart:async';

import 'package:talker_flutter/talker_flutter.dart';

import '../../shared/url_share.dart';
import 'chromium_cookies.dart';

/// Tier 2 login orchestration (план: «sign in via my browser»).
///
/// Открывает `https://soundcloud.com/signin` в системном браузере и
/// периодически опрашивает SQLite-cookie-сторы Brave/Chrome/Edge. Как только
/// в каком-то профиле появляется `oauth_token`, который валидирует
/// колбэк `validate` (живой `/me`-запрос), возвращаем его.
///
/// Контракт:
/// - `validate` — внешний фактчекер (`HttpSoundcloudApi.verifyToken`).
///   Мы не лезем в сеть напрямую; так лекго мокать в тестах и DI-замене API.
/// - `timeout` — общий бюджет (по плану 30s); при истечении вернётся
///   [BrowserLoginResult.timedOut], вызывающий эскалирует в Tier 3.
/// - [BrowserLoginSession.cancel] прекращает опрос немедленно и завершает
///   future c [BrowserLoginResult.cancelled].
class BrowserLogin {
  BrowserLogin({
    required this.cookies,
    Talker? talker,
    Duration pollInterval = const Duration(seconds: 2),
    Duration timeout = const Duration(seconds: 30),
  })  : _pollInterval = pollInterval,
        _timeout = timeout,
        _log = talker;

  final ChromiumCookies cookies;
  final Duration _pollInterval;
  final Duration _timeout;
  final Talker? _log;

  /// Одноразовая попытка прочитать токен из всех установленных браузеров
  /// (без открытия signin-страницы и без опроса). Удобно для Tier 1.
  ///
  /// Возвращает первый расшифрованный токен, ПРОШЕДШИЙ `validate`. Если
  /// ни один не валидируется — `null`.
  Future<BrowserPrescan?> prescan({
    required Future<bool> Function(String token) validate,
  }) async {
    final browsers = await cookies.detectInstalled();
    for (final b in browsers) {
      final token = await cookies.readOauthToken(b);
      if (token == null || token.isEmpty) continue;
      try {
        if (await validate(token)) {
          _log?.info('browser_login: prescan hit from ${b.label}');
          return BrowserPrescan(browser: b, token: token);
        }
      } catch (e, st) {
        _log?.warning(
          'browser_login: prescan validate failed for ${b.label}',
          e,
          st,
        );
      }
    }
    return null;
  }

  /// Запускает Tier 2: открывает signin-страницу и подписывается на
  /// поллер. Возвращает [BrowserLoginSession] — у неё `result` (future с
  /// итогом) и `cancel()`.
  BrowserLoginSession startLogin({
    required Future<bool> Function(String token) validate,
  }) {
    final completer = Completer<BrowserLoginResult>();
    Timer? poll;
    Timer? timeoutTimer;
    var stopped = false;
    var inFlight = false;
    String? lastChecked;

    void finish(BrowserLoginResult result) {
      if (stopped) return;
      stopped = true;
      poll?.cancel();
      timeoutTimer?.cancel();
      if (!completer.isCompleted) completer.complete(result);
    }

    Future<void> tick() async {
      if (stopped || inFlight) return;
      inFlight = true;
      try {
        final browsers = await cookies.detectInstalled();
        for (final b in browsers) {
          if (stopped) return;
          final token = await cookies.readOauthToken(b);
          if (token == null || token.isEmpty) continue;
          // Не валидируем повторно один и тот же токен — экономим /me.
          if (token == lastChecked) continue;
          lastChecked = token;
          try {
            if (await validate(token)) {
              _log?.info('browser_login: poll hit from ${b.label}');
              finish(
                BrowserLoginResult.success(
                  BrowserPrescan(browser: b, token: token),
                ),
              );
              return;
            }
          } catch (e, st) {
            _log?.warning(
              'browser_login: poll validate failed for ${b.label}',
              e,
              st,
            );
          }
        }
      } catch (e, st) {
        _log?.warning('browser_login: poll iteration failed', e, st);
      } finally {
        inFlight = false;
      }
    }

    // Открываем браузер в системном дефолте; ошибки молчком (best-effort —
    // юзер сам может перейти на soundcloud.com).
    unawaited(openExternalUrl('https://soundcloud.com/signin'));

    // Первый «tick» — почти сразу, чтобы поймать уже залогиненную сессию
    // (на которую браузер просто переключился новой вкладкой).
    Timer.run(tick);
    poll = Timer.periodic(_pollInterval, (_) => tick());
    timeoutTimer = Timer(_timeout, () => finish(BrowserLoginResult.timedOut()));

    return BrowserLoginSession._(
      completer.future,
      cancel: () => finish(BrowserLoginResult.cancelled()),
    );
  }
}

/// Результат одного цикла «открыть браузер → подождать → прочитать токен».
sealed class BrowserLoginResult {
  const BrowserLoginResult();
  factory BrowserLoginResult.success(BrowserPrescan hit) =
      BrowserLoginSuccess._;
  factory BrowserLoginResult.timedOut() = BrowserLoginTimedOut._;
  factory BrowserLoginResult.cancelled() = BrowserLoginCancelled._;
}

class BrowserLoginSuccess extends BrowserLoginResult {
  const BrowserLoginSuccess._(this.hit);
  final BrowserPrescan hit;
}

class BrowserLoginTimedOut extends BrowserLoginResult {
  const BrowserLoginTimedOut._();
}

class BrowserLoginCancelled extends BrowserLoginResult {
  const BrowserLoginCancelled._();
}

/// Найденный валидный токен + браузер-источник (для текста кнопки).
class BrowserPrescan {
  const BrowserPrescan({required this.browser, required this.token});
  final ChromiumBrowser browser;
  final String token;
}

/// Управляемый «handle» на Tier-2-сессию: можно дождаться `result` или
/// `cancel()` (диалог закрыт / юзер передумал).
class BrowserLoginSession {
  BrowserLoginSession._(this.result, {required void Function() cancel})
      : _cancel = cancel;

  final Future<BrowserLoginResult> result;
  final void Function() _cancel;

  void cancel() => _cancel();
}
