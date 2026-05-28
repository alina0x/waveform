import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Простое локальное хранилище OAuth-токена.
///
/// Раньше использовали `flutter_secure_storage` (Keychain), но на macOS с
/// app-sandbox без development-сертификата он либо не персистит, либо валит
/// сборку (`keychain-access-groups` требует подписанной команды разработчика).
/// Для OSS-десктопа кладём токен файлом в `getApplicationSupportDirectory()`
/// — это контейнер приложения (sandboxed, доступен только этому приложению и
/// текущему пользователю). OAuth-токен SoundCloud легко отзывается, так что
/// этого уровня изоляции достаточно.
class TokenStore {
  const TokenStore();

  static const _fileName = 'sc_oauth_token';

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<String?> read() async {
    final f = await _file();
    if (!await f.exists()) return null;
    final v = (await f.readAsString()).trim();
    return v.isEmpty ? null : v;
  }

  Future<void> write(String token) async {
    final f = await _file();
    await f.parent.create(recursive: true);
    // 0600 — только владелец читает (POSIX-плагин path_provider'а это уважает).
    await f.writeAsString(token, flush: true);
  }

  Future<void> delete() async {
    final f = await _file();
    if (await f.exists()) await f.delete();
  }
}
