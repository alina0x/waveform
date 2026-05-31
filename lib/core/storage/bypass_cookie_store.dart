import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persisted SoundCloud cookie jar used to bypass DataDome bot detection.
///
/// Why a separate file from [TokenStore]:
/// - OAuth tokens are a single value; cookie jar is a small map (datadome,
///   sc_tracking_anonymous_id, …) that grows as we discover which cookies
///   DataDome cross-references.
/// - Cookies are scraped from either the in-app WebView (after the user
///   solves a captcha there) or from the host browser's Chromium SQLite
///   (Tier 1). Either source may give us a partial jar, so we merge
///   instead of overwriting.
///
/// On-disk format: pretty JSON (`{ "datadome": "...", ... }`). Trivial to
/// inspect / delete if it goes stale, plus survives schema additions.
class BypassCookieStore {
  const BypassCookieStore();

  static const _fileName = 'sc_bypass_cookies.json';

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<Map<String, String>> read() async {
    try {
      final f = await _file();
      if (!await f.exists()) return const {};
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return const {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <String, String>{};
      decoded.forEach((k, v) {
        if (k is String && v is String && v.isNotEmpty) out[k] = v;
      });
      return out;
    } catch (_) {
      // Corrupted JSON / IO error → ignore, next scrape rebuilds it.
      return const {};
    }
  }

  /// Merge [incoming] into the on-disk jar, dropping any key whose value
  /// is empty. Persisted as pretty JSON for easy inspection.
  Future<Map<String, String>> merge(Map<String, String> incoming) async {
    final current = Map<String, String>.from(await read());
    var changed = false;
    incoming.forEach((k, v) {
      if (v.isEmpty) return;
      if (current[k] != v) {
        current[k] = v;
        changed = true;
      }
    });
    if (changed) {
      final f = await _file();
      await f.parent.create(recursive: true);
      await f.writeAsString(
        const JsonEncoder.withIndent('  ').convert(current),
        flush: true,
      );
    }
    return current;
  }

  Future<void> delete() async {
    final f = await _file();
    if (await f.exists()) await f.delete();
  }
}
