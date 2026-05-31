import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../log/talker.dart';
import '../storage/bypass_cookie_store.dart';

/// SoundCloud cookies known to participate in DataDome bot-detection.
///
/// `datadome` is the primary signal (the blessed session token); the rest
/// are cross-referenced — sending only `datadome` while a sibling like
/// `sc_tracking_anonymous_id` is missing makes DataDome treat the cookie
/// as foreign and re-challenge. The list is consumed by [WebviewLogin]
/// when harvesting cookies after sign-in / verification.
const List<String> kSoundcloudBypassCookies = [
  'datadome',
  'sc_tracking_anonymous_id',
  'sc_anonymous_id',
  'OptanonConsent',
];

/// Cached cookie jar used by the Dio interceptor to bypass SoundCloud's
/// DataDome anti-bot wall on mutating endpoints (`PUT /track_likes/…`,
/// `track_reposts/…`).
///
/// Source of truth is the in-app WebView: every sign-in flow and every
/// tap on "verify" in the blocked-action toast harvests SoundCloud's
/// cookie jar via `Webview.getAllCookies()` and persists it through
/// [adopt]. The persisted jar (`<appSupport>/sc_bypass_cookies.json`)
/// survives restarts so a single successful capture lasts ~a year (the
/// `datadome` cookie's Max-Age).
///
/// State is the rendered `Cookie:` header value
/// (`datadome=…; sc_tracking_anonymous_id=…`). Empty / null when no
/// bypass info is available yet — the interceptor just sends the request
/// without a Cookie header and falls through to the existing
/// `LikeOutcome.blocked` toast on the inevitable 403.
class DataDomeStore extends Notifier<String?> {
  static const _store = BypassCookieStore();
  Map<String, String> _jar = const {};

  @override
  String? build() {
    // Best-effort, fire-and-forget — never block app startup on disk I/O.
    Future.microtask(_load);
    return null;
  }

  Future<void> _load() async {
    _publish(await _store.read());
  }

  /// Re-read the persisted jar. Called by the Dio interceptor on a
  /// 403-DataDome to pick up a freshly-captured cookie set the user may
  /// have just adopted by signing in or completing verification.
  Future<void> refresh() async => _load();

  /// Persist a cookie jar captured outside this notifier (typically by
  /// `WebviewLogin` after the user signed in or completed verification).
  /// Merges with any existing entries — partial captures are valuable.
  Future<void> adopt(Map<String, String> cookies) async {
    if (cookies.isEmpty) return;
    final jar = await _store.merge(cookies);
    _publish(jar);
  }

  /// Drop the persisted jar — invoked on sign-out so a different user
  /// (or guest) doesn't inherit the previous DataDome session.
  Future<void> clear() async {
    await _store.delete();
    _jar = const {};
    if (ref.mounted) state = null;
  }

  /// Decrypted entries as a `name → value` map.
  Map<String, String> get jar => _jar;

  void _publish(Map<String, String> jar) {
    final log = ref.read(talkerProvider);
    _jar = Map.unmodifiable(jar);
    if (jar.isEmpty) {
      if (ref.mounted) state = null;
      return;
    }
    final hasDatadome = jar.containsKey('datadome');
    log.info(
      'datadome: jar loaded (${jar.keys.join(", ")})'
      '${hasDatadome ? "" : " — no datadome cookie yet, bypass inactive"}',
    );
    final header = jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
    if (ref.mounted) state = header;
  }
}

final dataDomeProvider = NotifierProvider<DataDomeStore, String?>(
  DataDomeStore.new,
);
