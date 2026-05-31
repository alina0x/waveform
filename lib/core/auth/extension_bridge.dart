import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:talker_flutter/talker_flutter.dart';

import '../../shared/url_share.dart';

/// Loopback-порт Tier 3. Hard-code'нут (план): extension знает его,
/// случайный порт пришлось бы как-то проброшать в манифест.
const int _kLoopbackPort = 47189;

/// Файлы расширения, упакованные в Flutter-бандл (см. pubspec.yaml
/// `flutter.assets`).
const List<String> _kExtensionAssets = [
  'assets/extension/manifest.json',
  'assets/extension/background.js',
  'assets/extension/icon-128.png',
];

/// Tier 3 — extension-bridge.
///
/// На случай когда даже расшифровать cookie не вышло (Chrome 127+ v20 /
/// другой пользователь / app-bound encryption): кладём bundled-extension в
/// `<appSupport>/waveform-bridge/`, поднимаем loopback-сервер на 127.0.0.1:47189
/// и просим юзера один раз загрузить unpacked-extension в chrome://extensions.
/// Дальше extension сам пушит токен в наш `POST /token`.
class ExtensionBridge {
  ExtensionBridge({Talker? talker}) : _log = talker;

  final Talker? _log;

  HttpServer? _server;
  StreamSubscription<HttpRequest>? _sub;
  Directory? _deployedDir;

  /// Путь, по которому будет лежать unpacked-extension. Стабилен между
  /// запусками — чтобы повторный «Load unpacked» не требовался.
  Future<Directory> extensionDir() async {
    final cached = _deployedDir;
    if (cached != null) return cached;
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}${Platform.pathSeparator}waveform-bridge');
    _deployedDir = dir;
    return dir;
  }

  /// Распаковывает bundled-extension на диск. Идемпотентно — перезаписывает
  /// файлы каждый раз (на случай обновления приложения).
  Future<Directory> deployExtension() async {
    final dir = await extensionDir();
    if (!await dir.exists()) await dir.create(recursive: true);

    for (final asset in _kExtensionAssets) {
      final bytes = (await rootBundle.load(asset)).buffer.asUint8List();
      final name = asset.split('/').last;
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.writeAsBytes(bytes, flush: true);
    }
    _log?.info('extension_bridge: deployed to ${dir.path}');
    return dir;
  }

  /// Поднимает loopback на 127.0.0.1:47189. Колбэк [onToken] вызывается
  /// каждый раз, когда extension успешно сделал POST. Колбэк сам решает
  /// валидировать ли токен и завершать ли диалог.
  ///
  /// Уже запущенный сервер не перепутываем — переиспользуем.
  Future<int> startLoopback({
    required void Function(String token) onToken,
  }) async {
    if (_server != null) return _server!.port;

    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      _kLoopbackPort,
      shared: false,
    );
    _server = server;
    _sub = server.listen((req) async {
      try {
        // Минимальный CORS — extension'у достаточно «*», нам — простота.
        req.response.headers
          ..set('Access-Control-Allow-Origin', '*')
          ..set('Access-Control-Allow-Methods', 'POST, OPTIONS')
          ..set('Access-Control-Allow-Headers', 'content-type');

        if (req.method == 'OPTIONS') {
          req.response.statusCode = HttpStatus.noContent;
          await req.response.close();
          return;
        }
        if (req.method != 'POST' || req.uri.path != '/token') {
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
          return;
        }

        final body = await utf8.decoder.bind(req).join();
        // Тело может быть как JSON `{"token":"..."}`, так и просто строка
        // — толерантны к обоим случаям.
        String? token;
        try {
          final json = jsonDecode(body);
          if (json is Map && json['token'] is String) {
            token = (json['token'] as String).trim();
          }
        } catch (_) {
          // Не JSON — попробуем как голую строку.
          final trimmed = body.trim();
          if (trimmed.isNotEmpty) token = trimmed;
        }

        if (token == null || token.isEmpty) {
          req.response.statusCode = HttpStatus.badRequest;
          await req.response.close();
          return;
        }

        req.response.statusCode = HttpStatus.ok;
        await req.response.close();

        // Передаём callback'у — он сам валидирует и решает что делать.
        onToken(token);
      } catch (e, st) {
        _log?.warning('extension_bridge: request handler failed', e, st);
        try {
          req.response.statusCode = HttpStatus.internalServerError;
          await req.response.close();
        } catch (_) {/* ignore — соединение могло уже умереть */}
      }
    });

    _log?.info(
      'extension_bridge: listening on http://127.0.0.1:${server.port}/token',
    );
    return server.port;
  }

  /// Идёт ли уже сервер.
  bool get isRunning => _server != null;

  /// Открывает chrome://extensions в дефолтном браузере + Explorer на
  /// каталоге с распакованным extension'ом. Юзеру остаётся только включить
  /// Developer mode → Load unpacked → выбрать открытую папку.
  Future<void> openInstallHelp() async {
    final dir = await extensionDir();
    // chrome://extensions работает в Chrome/Brave/Edge (как chrome-scheme).
    unawaited(openExternalUrl('chrome://extensions'));
    if (Platform.isWindows) {
      try {
        // start "" "<path>" — без `start` Process.run возьмёт explorer.exe и
        // вернёт код 1 даже на успехе. cmd.exe знает как открыть.
        await Process.run('explorer', [dir.path]);
      } catch (e, st) {
        _log?.warning('extension_bridge: failed to open explorer', e, st);
      }
    } else if (Platform.isMacOS) {
      try {
        await Process.run('open', [dir.path]);
      } catch (_) {/* ignore */}
    } else if (Platform.isLinux) {
      try {
        await Process.run('xdg-open', [dir.path]);
      } catch (_) {/* ignore */}
    }
  }

  /// Останавливает loopback. Безопасно вызывать многократно — простой no-op
  /// если уже не запущен.
  Future<void> stop() async {
    final sub = _sub;
    final server = _server;
    _sub = null;
    _server = null;
    try {
      await sub?.cancel();
    } catch (_) {/* ignore */}
    try {
      await server?.close(force: true);
    } catch (_) {/* ignore */}
  }
}
