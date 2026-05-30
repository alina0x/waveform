import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Простые пользовательские настройки (вид списка, тема, прочее), JSON-файлом
/// в `getApplicationSupportDirectory()` рядом с токеном. Один файл —
/// `prefs.json`, ключи плоские строки.
///
/// Используется и в [ViewModeController], и (в будущем) в экране настроек.
/// В тестах path_provider не отвечает — вызовы оборачивать через `unawaited`.
class PrefsStore {
  const PrefsStore();

  static const _fileName = 'prefs.json';

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<Map<String, dynamic>> _load() async {
    final f = await _file();
    if (!await f.exists()) return <String, dynamic>{};
    try {
      final raw = await f.readAsString();
      final j = jsonDecode(raw);
      return j is Map ? Map<String, dynamic>.from(j) : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<String?> readString(String key) async {
    final v = (await _load())[key];
    return v is String ? v : null;
  }

  Future<bool?> readBool(String key) async {
    final v = (await _load())[key];
    return v is bool ? v : null;
  }

  Future<void> writeString(String key, String value) => _write(key, value);

  Future<void> writeBool(String key, bool value) => _write(key, value);

  Future<void> _write(String key, Object value) async {
    final m = await _load();
    m[key] = value;
    final f = await _file();
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(m), flush: true);
  }

  Future<void> remove(String key) async {
    final m = await _load();
    if (m.remove(key) == null) return;
    final f = await _file();
    await f.writeAsString(jsonEncode(m), flush: true);
  }
}
