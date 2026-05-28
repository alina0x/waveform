import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'lastfm_constants.dart';

/// Подписанный клиент Last.fm REST API. md5-подпись по правилам Last.fm:
/// конкатенируем `k1v1k2v2…` в алфавитном порядке + shared_secret → md5 hex.
/// Подпись добавляется как `api_sig` параметр; `format=json` для ответа.
class LastfmClient {
  LastfmClient(this._dio);
  final Dio _dio;

  String _sign(Map<String, String> params) {
    final keys = params.keys.toList()..sort();
    final buf = StringBuffer();
    for (final k in keys) {
      buf
        ..write(k)
        ..write(params[k]);
    }
    buf.write(lastfmSharedSecret);
    return md5.convert(utf8.encode(buf.toString())).toString();
  }

  /// GET-вызов без подписи (для unauth-методов: `auth.getToken`).
  Future<Map<String, dynamic>> _get(Map<String, String> params) async {
    final res = await _dio.get(lastfmApiRoot, queryParameters: {
      ...params,
      'api_key': lastfmApiKey,
      'format': 'json',
    });
    return _asMap(res.data);
  }

  /// POST-вызов с подписью (для write-методов: scrobble, updateNowPlaying,
  /// getSession). Last.fm требует form-encoded тело.
  Future<Map<String, dynamic>> _post(Map<String, String> params) async {
    final signedParams = <String, String>{
      ...params,
      'api_key': lastfmApiKey,
    };
    signedParams['api_sig'] = _sign(signedParams);
    signedParams['format'] = 'json';
    final res = await _dio.post(
      lastfmApiRoot,
      data: signedParams,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
    return _asMap(res.data);
  }

  Map<String, dynamic> _asMap(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  /// Шаг 1 OAuth flow: получаем одноразовый token. Anon, не требует подписи.
  Future<String?> getAuthToken() async {
    if (!lastfmConfigured) return null;
    final res = await _get({'method': 'auth.getToken'});
    return res['token'] as String?;
  }

  /// Шаг 3: после того как пользователь авторизовал token в браузере, меняем
  /// его на постоянный session_key (привязан к Last.fm-аккаунту, не истекает).
  /// Возвращает (session_key, username) или null если token ещё не одобрен.
  Future<({String key, String name})?> getSession(String token) async {
    if (!lastfmConfigured) return null;
    final res = await _post({
      'method': 'auth.getSession',
      'token': token,
    });
    final session = _asMap(res['session']);
    final key = session['key'] as String?;
    final name = session['name'] as String?;
    if (key == null || name == null) return null;
    return (key: key, name: name);
  }

  /// «Сейчас играет». Шлём при смене трека.
  Future<void> updateNowPlaying({
    required String artist,
    required String track,
    required Duration duration,
    String? album,
    required String sessionKey,
  }) async {
    if (!lastfmConfigured) return;
    await _post({
      'method': 'track.updateNowPlaying',
      'artist': artist,
      'track': track,
      if (album != null && album.isNotEmpty) 'album': album,
      'duration': '${duration.inSeconds}',
      'sk': sessionKey,
    });
  }

  /// Постоянная запись в историю прослушиваний. timestamp = когда трек *начался*.
  Future<void> scrobble({
    required String artist,
    required String track,
    required DateTime startedAt,
    Duration? duration,
    String? album,
    required String sessionKey,
  }) async {
    if (!lastfmConfigured) return;
    await _post({
      'method': 'track.scrobble',
      'artist': artist,
      'track': track,
      if (album != null && album.isNotEmpty) 'album': album,
      if (duration != null) 'duration': '${duration.inSeconds}',
      'timestamp':
          '${startedAt.millisecondsSinceEpoch ~/ 1000}',
      'sk': sessionKey,
    });
  }
}
