import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/prefs_store.dart';
import 'lastfm_client.dart';

/// Сохранённая Last.fm-сессия (session_key + username). null = не подключён.
class LastfmSession {
  const LastfmSession({required this.key, required this.name});
  final String key;
  final String name;
}

class LastfmSessionController extends Notifier<LastfmSession?> {
  static const _store = PrefsStore();
  static const _keyKey = 'lastfm_session_key';
  static const _keyName = 'lastfm_username';

  @override
  LastfmSession? build() {
    _restore();
    return null;
  }

  Future<void> _restore() async {
    try {
      final k = await _store.readString(_keyKey);
      final n = await _store.readString(_keyName);
      if (k != null && k.isNotEmpty && n != null) {
        state = LastfmSession(key: k, name: n);
      }
    } catch (_) {}
  }

  void set(LastfmSession s) {
    state = s;
    unawaited(
      _safe(() async {
        await _store.writeString(_keyKey, s.key);
        await _store.writeString(_keyName, s.name);
      }),
    );
  }

  void clear() {
    state = null;
    unawaited(
      _safe(() async {
        await _store.remove(_keyKey);
        await _store.remove(_keyName);
      }),
    );
  }

  Future<void> _safe(Future<void> Function() op) async {
    try {
      await op();
    } catch (_) {}
  }
}

final lastfmSessionProvider =
    NotifierProvider<LastfmSessionController, LastfmSession?>(
      LastfmSessionController.new,
    );

/// Lazy LastfmClient переиспользует тот же Dio, что и SoundCloud-клиент.
final lastfmClientProvider = Provider<LastfmClient>((ref) {
  // Простой Dio без логгеров — Last.fm-ответы шумные.
  final dio = Dio();
  ref.onDispose(dio.close);
  return LastfmClient(dio);
});
