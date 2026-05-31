import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:ffi/ffi.dart' as ffi;
import 'package:sqlite3/sqlite3.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:win32/win32.dart' as w32;

/// Семейство Chromium-браузеров, у которых одинаковый формат cookie-стора
/// (SQLite + per-user AES-GCM ключ, обёрнутый DPAPI).
enum ChromiumBrand {
  brave('Brave'),
  chrome('Chrome'),
  edge('Edge');

  const ChromiumBrand(this.label);
  final String label;
}

/// Один найденный установленный Chromium-браузер.
///
/// `userDataDir` — корень `User Data`, под ним лежат `Local State` (с
/// зашифрованным master-ключом) и профили (`Default`, `Profile N`).
class ChromiumBrowser {
  const ChromiumBrowser({required this.brand, required this.userDataDir});
  final ChromiumBrand brand;
  final String userDataDir;

  String get label => brand.label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChromiumBrowser &&
          other.brand == brand &&
          other.userDataDir == userDataDir;

  @override
  int get hashCode => Object.hash(brand, userDataDir);
}

/// Источник `oauth_token` cookie из браузера пользователя.
///
/// Tier 1/2 в login-диалоге: до того как тащить юзера в WebView или
/// extension-bridge, пробуем достать готовый токен из уже открытой Brave/
/// Chrome/Edge-сессии.
///
/// Шифрование Chromium (Windows):
/// 1. `Local State` содержит `os_crypt.encrypted_key` — base64 DPAPI-blob
///    с префиксом `"DPAPI"`.
/// 2. После DPAPI-распаковки получается 32-байтовый AES-256 ключ.
/// 3. Каждый cookie в SQLite (`Network/Cookies`) — это blob с префиксом
///    `v10` (AES-GCM, nonce=blob[3..15], ciphertext=blob[15..-16],
///    tag=blob[-16..]) или `v20` (app-bound, Chrome 127+) — последний
///    мы не вскрываем, это и есть точка эскалации в Tier 3 (extension).
class ChromiumCookies {
  ChromiumCookies({Talker? talker}) : _log = talker;

  final Talker? _log;
  // DPAPI — дорогой syscall; ключ для каждого браузера unwrap'ится один
  // раз за жизнь экземпляра (Tier 1 → ещё раз Tier 2).
  final Map<String, Uint8List?> _keyCache = {};

  // ---------------------------------------------------------------------------
  // Обнаружение установленных браузеров.
  // ---------------------------------------------------------------------------

  /// Возвращает Chromium-семейство браузеров, у которых на диске есть
  /// директория `User Data`. На non-Windows платформах — пусто (см. план,
  /// Linux/macOS — отдельный заход).
  Future<List<ChromiumBrowser>> detectInstalled() async {
    if (!Platform.isWindows) return const [];
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData == null || localAppData.isEmpty) return const [];

    final candidates = <ChromiumBrowser>[
      ChromiumBrowser(
        brand: ChromiumBrand.brave,
        userDataDir: '$localAppData\\BraveSoftware\\Brave-Browser\\User Data',
      ),
      ChromiumBrowser(
        brand: ChromiumBrand.chrome,
        userDataDir: '$localAppData\\Google\\Chrome\\User Data',
      ),
      ChromiumBrowser(
        brand: ChromiumBrand.edge,
        userDataDir: '$localAppData\\Microsoft\\Edge\\User Data',
      ),
    ];

    final found = <ChromiumBrowser>[];
    for (final b in candidates) {
      if (await Directory(b.userDataDir).exists()) found.add(b);
    }
    return found;
  }

  // ---------------------------------------------------------------------------
  // Чтение Soundcloud-cookie (oauth_token / datadome / etc).
  // ---------------------------------------------------------------------------

  /// Возвращает первый расшифрованный `oauth_token` cookie для
  /// `soundcloud.com` из любого профиля браузера [b].
  ///
  /// Тонкая обёртка над [readSoundcloudCookie] для обратной совместимости с
  /// логин-флоу.
  Future<String?> readOauthToken(ChromiumBrowser b) =>
      readSoundcloudCookie(b, 'oauth_token');

  /// Возвращает первый расшифрованный SoundCloud-cookie с указанным [name]
  /// (например `datadome` для обхода bot-проверки) из любого профиля браузера.
  ///
  /// `null` если:
  /// - master-ключ нерасшифровываем (другой пользователь / повреждённый
  ///   `Local State`),
  /// - все cookies в формате `v20` (app-bound) — эскалируем в Tier 3,
  /// - такого cookie просто нет (юзер не был на soundcloud.com).
  ///
  /// Метод НЕ валидирует cookie — это обязанность вызывающего.
  Future<String?> readSoundcloudCookie(ChromiumBrowser b, String name) async {
    if (!Platform.isWindows) return null;
    final key = await _masterKey(b);
    if (key == null) return null;
    for (final profile in await _profilesWithCookies(b)) {
      final value = await _readProfileCookie(profile, name, key);
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  /// Тotal истории профилей под `User Data` — `Default` плюс
  /// `Profile 1`/`Profile 2`/... — у которых есть Network/Cookies.
  Future<List<String>> _profilesWithCookies(ChromiumBrowser b) async {
    final root = Directory(b.userDataDir);
    if (!await root.exists()) return const [];
    final out = <String>[];
    try {
      await for (final e in root.list(followLinks: false)) {
        if (e is! Directory) continue;
        final name = _basename(e.path);
        if (name != 'Default' && !name.startsWith('Profile ')) continue;
        final cookies = File('${e.path}\\Network\\Cookies');
        if (await cookies.exists()) out.add(e.path);
      }
    } on FileSystemException catch (e, st) {
      _log?.warning(
        'chromium_cookies: failed listing profiles in ${b.userDataDir}',
        e,
        st,
      );
    }
    return out;
  }

  Future<String?> _readProfileCookie(
    String profileDir,
    String name,
    Uint8List masterKey,
  ) async {
    final src = File('$profileDir\\Network\\Cookies');
    if (!await src.exists()) return null;

    // База залочена пока браузер запущен — копируем во временный файл и
    // открываем readOnly+immutable, чтобы sqlite не пытался писать WAL.
    final tempDir = await Directory.systemTemp.createTemp('waveform-cookies-');
    final tempPath = '${tempDir.path}\\Cookies.sqlite';
    try {
      await src.copy(tempPath);

      Database? db;
      try {
        db = sqlite3.open(
          'file:${_toUri(tempPath)}?mode=ro&immutable=1',
          mode: OpenMode.readOnly,
          uri: true,
        );
        final rs = db.select(
          "SELECT encrypted_value FROM cookies "
          "WHERE name = ? AND host_key LIKE '%soundcloud.com'",
          [name],
        );
        for (final row in rs) {
          final blob = row['encrypted_value'];
          if (blob is! Uint8List || blob.isEmpty) continue;
          final decoded = await _decryptCookie(blob, masterKey);
          if (decoded == null) continue;
          final trimmed = decoded.trim();
          if (trimmed.isEmpty) continue;
          return trimmed;
        }
        return null;
      } finally {
        db?.dispose();
      }
    } catch (e, st) {
      _log?.warning(
        'chromium_cookies: failed reading $profileDir cookies',
        e,
        st,
      );
      return null;
    } finally {
      // Best-effort cleanup; ОС всё равно подметёт %TEMP%.
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {/* ignore */}
    }
  }

  // ---------------------------------------------------------------------------
  // Master key (Local State → DPAPI → 32-byte AES key).
  // ---------------------------------------------------------------------------

  Future<Uint8List?> _masterKey(ChromiumBrowser b) async {
    final cacheKey = b.userDataDir;
    if (_keyCache.containsKey(cacheKey)) return _keyCache[cacheKey];
    final key = await _unwrapMasterKey(b.userDataDir);
    _keyCache[cacheKey] = key;
    return key;
  }

  Future<Uint8List?> _unwrapMasterKey(String userDataDir) async {
    final stateFile = File('$userDataDir\\Local State');
    if (!await stateFile.exists()) return null;
    try {
      final raw = await stateFile.readAsString();
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      final osCrypt = json['os_crypt'];
      if (osCrypt is! Map<String, dynamic>) return null;
      final b64 = osCrypt['encrypted_key'];
      if (b64 is! String || b64.isEmpty) return null;
      final blob = base64Decode(b64);
      // Префикс "DPAPI" (ровно 5 ASCII-байт) — версионер Chromium'а.
      // Без него мы по адресу не туда (CryptUnprotectData упадёт с
      // BAD_DATA) — лучше сразу отказать.
      if (blob.length < 5 || !_startsWithAscii(blob, 'DPAPI')) return null;
      final dpapiBlob = Uint8List.fromList(blob.sublist(5));
      return _cryptUnprotect(dpapiBlob);
    } catch (e, st) {
      _log?.warning(
        'chromium_cookies: master-key unwrap failed for $userDataDir',
        e,
        st,
      );
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Cookie decryption.
  // ---------------------------------------------------------------------------

  /// Расшифровывает один cookie-blob. Возвращает `null` если префикс
  /// `v20` (app-bound, не поддерживается из стороннего процесса без
  /// elevation — для этого есть extension-bridge).
  Future<String?> _decryptCookie(Uint8List blob, Uint8List masterKey) async {
    if (blob.length < 3) return null;
    if (_startsWithAscii(blob, 'v10')) {
      return _aesGcmDecrypt(blob, masterKey);
    }
    if (_startsWithAscii(blob, 'v20')) {
      // App-bound (Chrome 127+) — Tier 3.
      return null;
    }
    // Очень старый Chrome (до v10) — blob как есть DPAPI-обёрнут.
    final out = _cryptUnprotect(blob);
    if (out == null) return null;
    try {
      return utf8.decode(out, allowMalformed: false);
    } on FormatException {
      return null;
    }
  }

  Future<String?> _aesGcmDecrypt(Uint8List blob, Uint8List masterKey) async {
    // Layout: [3-byte "v10"][12-byte nonce][ciphertext][16-byte GCM tag]
    if (blob.length < 3 + 12 + 16) return null;
    final nonce = blob.sublist(3, 15);
    final cipherText = blob.sublist(15, blob.length - 16);
    final tag = blob.sublist(blob.length - 16);
    try {
      final algorithm = AesGcm.with256bits();
      final clear = await algorithm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(tag)),
        secretKey: SecretKey(masterKey),
      );
      return utf8.decode(clear, allowMalformed: false);
    } on SecretBoxAuthenticationError {
      // Не наш мастер-ключ (например, профиль скопирован с другой машины).
      return null;
    } on FormatException {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers.
  // ---------------------------------------------------------------------------

  static bool _startsWithAscii(Uint8List blob, String ascii) {
    if (blob.length < ascii.length) return false;
    for (var i = 0; i < ascii.length; i++) {
      if (blob[i] != ascii.codeUnitAt(i)) return false;
    }
    return true;
  }

  static String _basename(String p) {
    final i = p.lastIndexOf(RegExp(r'[\\/]'));
    return i < 0 ? p : p.substring(i + 1);
  }

  /// sqlite3 `file:` URI требует прямых слэшей.
  static String _toUri(String windowsPath) =>
      windowsPath.replaceAll('\\', '/');
}

// =============================================================================
// Win32 DPAPI bridge.
// =============================================================================

/// Распаковывает blob, зашифрованный `CryptProtectData` под текущим user-SID.
/// Возвращает `null` при любой ошибке Win32 — наверху мы трактуем это как
/// «не наш профиль» и не падаем.
Uint8List? _cryptUnprotect(Uint8List ciphertext) {
  final inBlob = ffi.calloc<w32.CRYPT_INTEGER_BLOB>();
  final outBlob = ffi.calloc<w32.CRYPT_INTEGER_BLOB>();
  final inBuf = ffi.calloc<Uint8>(ciphertext.length);
  try {
    inBuf.asTypedList(ciphertext.length).setAll(0, ciphertext);
    inBlob.ref
      ..cbData = ciphertext.length
      ..pbData = inBuf;

    final result = w32.CryptUnprotectData(
      inBlob,
      nullptr, // ppszDataDescr
      nullptr, // pOptionalEntropy
      nullptr, // pPromptStruct
      0, // dwFlags
      outBlob,
    );
    if (!result.value) return null;

    final cb = outBlob.ref.cbData;
    if (cb <= 0) return null;
    // Копируем в Dart heap; буфер на стороне ОС освободим LocalFree.
    final out = Uint8List.fromList(outBlob.ref.pbData.asTypedList(cb));
    w32.LocalFree(w32.HLOCAL(outBlob.ref.pbData));
    return out;
  } finally {
    ffi.calloc.free(inBuf);
    ffi.calloc.free(inBlob);
    ffi.calloc.free(outBlob);
  }
}
