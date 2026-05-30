import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../log/talker.dart';
import '../storage/token_store.dart';

/// Состояние авторизации SoundCloud.
///
/// [clientId] — ключ приложения (нужен на каждом запросе, один на всех,
/// НЕ идентифицирует юзера). [userToken] — персональный OAuth Bearer,
/// появляется после входа (личный stream/library/likes/posting).
///
/// Вход — через настоящую страницу логина SoundCloud в embedded WebView
/// (см. webview_login.dart); сырые пароли мы не храним.
class SoundcloudAuth {
  const SoundcloudAuth({this.clientId, this.userToken});

  final String? clientId;
  final String? userToken;

  bool get hasClientId => clientId != null && clientId!.isNotEmpty;
  bool get isAuthenticated => userToken != null && userToken!.isNotEmpty;

  SoundcloudAuth copyWith({String? clientId, String? userToken}) =>
      SoundcloudAuth(
        clientId: clientId ?? this.clientId,
        userToken: userToken ?? this.userToken,
      );

  SoundcloudAuth signedOut() => SoundcloudAuth(clientId: clientId);
}

class AuthController extends Notifier<SoundcloudAuth> {
  static const _store = TokenStore();

  @override
  SoundcloudAuth build() {
    _restore();
    return const SoundcloudAuth();
  }

  /// Подтягиваем сохранённый токен при старте (best-effort; в тестах плагина
  /// path_provider нет — глушим).
  Future<void> _restore() async {
    try {
      final token = await _store.read();
      if (token != null && token.isNotEmpty) {
        state = state.copyWith(userToken: token);
        ref.read(talkerProvider).info('auth: restored token ${_mask(token)}');
      } else {
        ref.read(talkerProvider).info('auth: no stored token');
      }
    } catch (e, st) {
      // Видимая ошибка → проблема с keychain-entitlement/доступом, а не «нет токена».
      ref.read(talkerProvider).warning('auth: restore failed', e, st);
    }
  }

  // Маскируем токен в логах: видно форму (`2-…` = пользовательский), не секрет.
  String _mask(String t) => t.length <= 10
      ? '***'
      : '${t.substring(0, 6)}…${t.substring(t.length - 3)}';

  /// client_id добывается автоматически из веб-бандла (как в yt-dlp/FetchClientID).
  void setClientId(String id) => state = state.copyWith(clientId: id);

  /// Сохраняем токен после входа. Состояние ставим сразу; запись на диск —
  /// детачем (не блокируем UI/тесты, где плагина path_provider нет).
  void signIn(String userToken) {
    state = state.copyWith(userToken: userToken);
    ref
        .read(talkerProvider)
        .info(
          'auth: signIn token ${_mask(userToken)} (len ${userToken.length})',
        );
    unawaited(_safe(() => _store.write(userToken)));
  }

  void signOut() {
    ref.read(talkerProvider).info('auth: signOut');
    state = state.signedOut();
    unawaited(_safe(() => _store.delete()));
  }

  Future<void> _safe(Future<void> Function() op) async {
    try {
      await op();
    } catch (e, st) {
      ref.read(talkerProvider).warning('auth: storage op failed', e, st);
    }
  }
}

final authControllerProvider = NotifierProvider<AuthController, SoundcloudAuth>(
  AuthController.new,
);
