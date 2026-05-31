// ignore_for_file: avoid_print
//
// Tier 3 standalone smoke: stand up the loopback, validate any token the
// extension posts, log result. Run this, then in Brave:
//   1. Open  brave://extensions
//   2. Toggle "Developer mode" (top right)
//   3. "Load unpacked" → pick waveform/assets/extension/
//   4. (Optionally) reload soundcloud.com — extension also posts on install.
// First valid oauth_token causes the script to print ✓ and exit.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:waveform_app/core/api/client_id_resolver.dart';

const int _port = 47189;

String _mask(String t) => t.length <= 10
    ? '***'
    : '${t.substring(0, 6)}…${t.substring(t.length - 3)}';

Future<bool> _verify(Dio dio, ClientIdResolver ids, String token) async {
  try {
    final cid = await ids.get();
    final res = await dio.get(
      'https://api-v2.soundcloud.com/me',
      queryParameters: {'client_id': cid},
      options: Options(headers: {'Authorization': 'OAuth $token'}),
    );
    final data = res.data;
    if (data is Map && data['id'] != null) {
      print('   /me → id=${data['id']} '
          '(${data['username'] ?? data['permalink'] ?? '?'})');
      return true;
    }
    print('   /me → 200 без id (guest?)');
    return false;
  } on DioException catch (e) {
    print('   /me failed: ${e.response?.statusCode} ${e.message}');
    return false;
  }
}

Future<void> main() async {
  final dio = Dio();
  final ids = ClientIdResolver(dio);
  final done = Completer<void>();

  final server =
      await HttpServer.bind(InternetAddress.loopbackIPv4, _port, shared: false);
  print('listening on http://127.0.0.1:$_port/token');
  print('\nLoad the unpacked extension at:');
  print('  ${File('assets/extension/manifest.json').absolute.parent.path}');
  print('\nWaiting for the extension to post a token…\n');

  server.listen((req) async {
    req.response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'POST, OPTIONS')
      ..set('Access-Control-Allow-Headers', 'content-type');
    if (req.method == 'OPTIONS') {
      req.response.statusCode = 204;
      await req.response.close();
      return;
    }
    if (req.method != 'POST' || req.uri.path != '/token') {
      req.response.statusCode = 404;
      await req.response.close();
      return;
    }
    final body = await utf8.decoder.bind(req).join();
    String? token;
    String? reason;
    try {
      final m = jsonDecode(body);
      if (m is Map) {
        token = (m['token'] as String?)?.trim();
        reason = m['reason'] as String?;
      }
    } catch (_) {
      token = body.trim();
    }
    req.response.statusCode = 200;
    await req.response.close();
    if (token == null || token.isEmpty) {
      print('POST /token  empty body');
      return;
    }
    print('POST /token  reason=$reason  token=${_mask(token)} len=${token.length}');
    final ok = await _verify(dio, ids, token);
    if (ok) {
      print('\n✓ Tier 3 verified end-to-end.');
      if (!done.isCompleted) done.complete();
    } else {
      print('  (not a user token; keep waiting for a different cookie change)');
    }
  });

  // Hard timeout so the script doesn't hang forever.
  Timer(const Duration(minutes: 5), () {
    if (!done.isCompleted) {
      print('\n× timed out after 5 min. Did you load the extension?');
      done.complete();
    }
  });

  await done.future;
  await server.close(force: true);
}
