import 'dart:async';
import 'dart:convert';

import 'package:talker_flutter/talker_flutter.dart';

import 'js_runner.dart';

/// Выполняет write-запросы api-v2 изнутри настоящего браузера (webview), чтобы
/// пройти DataDome (TLS/JA3 как у браузера + живая datadome-cookie). Подробности
/// — в spec 2026-06-10-account-reliability-webview-writes.
class WebviewApiExecutor {
  WebviewApiExecutor({
    required Future<JsRunner> Function() createRunner,
    required Future<String?> Function() tokenGetter,
    required Future<String> Function() clientIdGetter,
    required Talker log,
    this.pollInterval = const Duration(milliseconds: 150),
    this.maxPolls = 60,
    this.warmAttempts = 8,
    this.warmUrl = 'https://soundcloud.com',
  })  : _createRunner = createRunner,
        _tokenGetter = tokenGetter,
        _clientIdGetter = clientIdGetter,
        _log = log;

  final Future<JsRunner> Function() _createRunner;
  final Future<String?> Function() _tokenGetter;
  final Future<String> Function() _clientIdGetter;
  final Talker _log;
  final Duration pollInterval;
  final int maxPolls;
  final int warmAttempts;
  final String warmUrl;

  static const _readExpr = 'window.__wfRes';

  JsRunner? _runner;
  bool _warm = false;
  Future<void> _tail = Future<void>.value();

  /// Выполнить write; вернуть HTTP-статус. Запросы сериализуются.
  Future<int> send({required String method, required String path}) =>
      _serialize(() => _sendInner(method, path));

  Future<int> _sendInner(String method, String path) async {
    await _ensureWarm();
    var status = await _execFetch(method, path);
    if (status == 403) {
      _log.info('[executor] 403 → re-warm + retry');
      _warm = false;
      await _ensureWarm();
      status = await _execFetch(method, path);
    }
    return status;
  }

  Future<void> _ensureRunner() async {
    _runner ??= await _createRunner();
  }

  Future<void> _ensureWarm() async {
    if (_warm) return;
    await _ensureRunner();
    await _runner!.launch(warmUrl);
    for (var i = 0; i < warmAttempts; i++) {
      try {
        final s = await _execFetch('GET', '/me');
        if (s != 403) {
          _warm = true;
          return;
        }
      } catch (_) {
        // окно ещё грузится — повторим
      }
      await Future<void>.delayed(pollInterval);
    }
    throw StateError('webview warm-up failed (DataDome)');
  }

  Future<int> _execFetch(String method, String path) async {
    final token = await _tokenGetter();
    if (token == null || token.isEmpty) {
      throw StateError('executor: no oauth token');
    }
    final cid = await _clientIdGetter();
    await _runner!.eval(_script(method, path, token, cid));
    for (var i = 0; i < maxPolls; i++) {
      await Future<void>.delayed(pollInterval);
      final r = await _runner!.eval(_readExpr);
      if (r != null && r != 'null' && r.isNotEmpty) {
        final m = jsonDecode(r) as Map<String, dynamic>;
        return (m['status'] as num).toInt();
      }
    }
    throw TimeoutException('webview fetch timed out: $method $path');
  }

  String _script(String method, String path, String token, String cid) {
    final sep = path.contains('?') ? '&' : '?';
    final url = 'https://api-v2.soundcloud.com$path${sep}client_id=$cid';
    return '''
window.__wfRes = null;
(async () => {
  try {
    const r = await fetch("$url", { method: "$method", headers: { Authorization: "OAuth $token" }, credentials: "include" });
    window.__wfRes = JSON.stringify({ status: r.status });
  } catch (e) { window.__wfRes = JSON.stringify({ status: 0, err: String(e) }); }
})();
''';
  }

  Future<T> _serialize<T>(Future<T> Function() op) {
    final run = _tail.then((_) => op());
    _tail = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// Best-effort фоновый прогрев (после signIn), чтобы первый лайк не ждал.
  Future<void> prewarm() async {
    try {
      await _serialize(_ensureWarm);
    } catch (e, st) {
      _log.warning('[executor] prewarm failed', e, st);
    }
  }

  Future<void> dispose() async {
    try {
      await _runner?.close();
    } catch (_) {}
    _runner = null;
    _warm = false;
  }
}
