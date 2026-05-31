import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/colors.dart';
import '../../core/api/datadome_store.dart';
import '../../core/api/providers.dart';
import '../../core/api/soundcloud_auth.dart';
import '../../core/api/webview_login.dart';
import '../../core/auth/browser_login.dart';
import '../../core/auth/chromium_cookies.dart';
import '../../core/auth/extension_bridge.dart';
import '../../core/log/talker.dart';
import '../../shared/url_share.dart';
import '../../shared/widgets/pressable.dart';

Future<void> showLoginDialog(BuildContext context) => showDialog(
  context: context,
  barrierColor: AppColors.bg.withValues(alpha: 0.6),
  builder: (_) => const _LoginDialog(),
);

/// UI state for the auto-grab subsystem (Tier 1/2/3).
///
/// `idle`            — nothing started yet; pre-scan may be silently running.
/// `prescanned`      — Tier 1 hit: token decrypted from a closed-state cookie.
/// `pollingBrowser`  — Tier 2: SoundCloud signin opened, polling for cookie.
/// `needExtension`   — Tier 2 timed out or cookies unreadable; show Tier 3 CTA.
/// `awaitingBridge`  — Tier 3 active: extension deployed, loopback waiting.
enum _AutoState { idle, prescanned, pollingBrowser, needExtension, awaitingBridge }

class _LoginDialog extends ConsumerStatefulWidget {
  const _LoginDialog();

  @override
  ConsumerState<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends ConsumerState<_LoginDialog> {
  final _token = TextEditingController();
  bool _busy = false;
  bool _showHelp = false;
  String? _hint;

  // Auto-grab pipeline state.
  var _auto = _AutoState.idle;
  BrowserPrescan? _prescanHit; // Tier 1 result, if any.
  BrowserLoginSession? _pollSession; // Tier 2 handle (cancellable).
  ExtensionBridge? _bridge; // Tier 3 server; lazily created.
  bool _disposed = false;

  // Cached helpers — shared across tiers; one ChromiumCookies instance
  // keeps the per-browser master-key cache (DPAPI unwrap is the slow part).
  late final ChromiumCookies _cookies;
  late final BrowserLogin _browserLogin;

  @override
  void initState() {
    super.initState();
    _token.addListener(() => setState(() {}));
    _cookies = ChromiumCookies(talker: ref.read(talkerProvider));
    _browserLogin = BrowserLogin(
      cookies: _cookies,
      talker: ref.read(talkerProvider),
    );
    if (Platform.isWindows) {
      // Tier 1 pre-scan — silent, best-effort. Renders a one-tap button if
      // a logged-in soundcloud session is already on disk and decryptable.
      // (For Chrome 127+ v20 cookies + browser-running Brave this is a
      // no-op; the user will fall through to Tier 2/3 anyway.)
      unawaited(_prescan());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pollSession?.cancel();
    unawaited(_bridge?.stop());
    _token.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (_disposed || !mounted) return;
    setState(fn);
  }

  // ---------------------------------------------------------------------------
  // Tier 1 — silent pre-scan.
  // ---------------------------------------------------------------------------

  Future<void> _prescan() async {
    final api = ref.read(soundcloudApiProvider);
    try {
      final hit = await _browserLogin.prescan(validate: api.verifyToken);
      if (hit == null) return;
      _safeSetState(() {
        _prescanHit = hit;
        _auto = _AutoState.prescanned;
      });
    } catch (e, st) {
      ref.read(talkerProvider).warning('login_dialog: prescan failed', e, st);
    }
  }

  void _usePrescan() {
    final hit = _prescanHit;
    if (hit == null) return;
    _done(hit.token);
  }

  // ---------------------------------------------------------------------------
  // Tier 2 — open browser, poll cookies.
  // ---------------------------------------------------------------------------

  Future<void> _browserPoll() async {
    final api = ref.read(soundcloudApiProvider);
    _pollSession?.cancel();
    _safeSetState(() {
      _auto = _AutoState.pollingBrowser;
      _hint = null;
    });
    final session = _browserLogin.startLogin(validate: api.verifyToken);
    _pollSession = session;
    final result = await session.result;
    if (_disposed) return;
    _pollSession = null;
    switch (result) {
      case BrowserLoginSuccess(:final hit):
        _done(hit.token);
      case BrowserLoginCancelled():
        _safeSetState(() => _auto = _AutoState.idle);
      case BrowserLoginTimedOut():
        _safeSetState(() => _auto = _AutoState.needExtension);
    }
  }

  void _cancelPoll() {
    _pollSession?.cancel();
    _pollSession = null;
    _safeSetState(() => _auto = _AutoState.idle);
  }

  // ---------------------------------------------------------------------------
  // Tier 3 — extension bridge (loopback + unpacked extension).
  // ---------------------------------------------------------------------------

  Future<void> _startExtensionBridge() async {
    final api = ref.read(soundcloudApiProvider);
    _safeSetState(() => _auto = _AutoState.awaitingBridge);
    final bridge = _bridge ??= ExtensionBridge(talker: ref.read(talkerProvider));
    try {
      await bridge.deployExtension();
      await bridge.startLoopback(
        onToken: (token) async {
          // Validate on the app side — extension may post a guest token
          // pre-login; only `/me`-valid tokens close the dialog.
          if (!await api.verifyToken(token)) return;
          if (_disposed) return;
          _done(token);
        },
      );
      await bridge.openInstallHelp();
    } catch (e, st) {
      ref
          .read(talkerProvider)
          .warning('login_dialog: extension bridge setup failed', e, st);
      _safeSetState(() => _hint = 'failed to set up helper extension — see logs');
    }
  }

  // ---------------------------------------------------------------------------
  // Existing paths.
  // ---------------------------------------------------------------------------

  void _done(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) return;
    _pollSession?.cancel();
    unawaited(_bridge?.stop());
    ref.read(authControllerProvider.notifier).signIn(trimmed);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _webviewLogin() async {
    _safeSetState(() {
      _busy = true;
      _hint = null;
    });
    try {
      if (!await WebviewLogin.available()) {
        _safeSetState(() => _hint = 'webview unavailable — paste token below');
        return;
      }
      final api = ref.read(soundcloudApiProvider);
      final capture = await WebviewLogin.signIn(validate: api.verifyToken);
      // Persist the DataDome bypass jar SoundCloud handed out while the
      // user signed in. Empty jar is harmless (just no-op on the
      // interceptor). Do this before _done so the first authed request
      // already sees the cookies.
      if (capture.cookies.isNotEmpty) {
        await ref.read(dataDomeProvider.notifier).adopt(capture.cookies);
      }
      final token = capture.token;
      if (token != null && token.isNotEmpty) {
        _done(token);
        return;
      }
      _safeSetState(() => _hint = "couldn't read token — paste it below");
    } catch (e) {
      _safeSetState(() => _hint = 'login failed — paste token below');
    } finally {
      _safeSetState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build.
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppTheme.borderRadius),
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: AppTheme.borderRadius,
          border: AppTheme.border(),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'sign in',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textHi,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'log in with your free SoundCloud account',
              style: AppTheme.mono(size: 11, color: AppColors.textMid),
            ),
            const SizedBox(height: 20),
            // Tier 1 — pre-scan hit, if any. Appears above the primary path.
            if (_auto == _AutoState.prescanned && _prescanHit != null) ...[
              _PrimaryButton(
                label: 'use ${_prescanHit!.browser.label} session',
                onTap: _busy ? null : _usePrescan,
              ),
              const SizedBox(height: 10),
            ],
            _PrimaryButton(
              label: _busy
                  ? 'waiting for sign-in…'
                  : 'continue with SoundCloud',
              busy: _busy,
              onTap: _busy ? null : _webviewLogin,
            ),
            // Tier 2 + 3 entry points (Windows-only — Brave/Chrome/Edge live
            // on %LOCALAPPDATA% and Tier 1's reader/Tier 3's loopback are
            // Windows-tuned. macOS/Linux Keychain/libsecret = follow-up).
            if (Platform.isWindows) ...[
              const SizedBox(height: 10),
              _SecondaryButton(
                label: _auto == _AutoState.pollingBrowser
                    ? 'waiting for browser sign-in…'
                    : 'sign in via my browser',
                busy: _auto == _AutoState.pollingBrowser,
                onTap:
                    _auto == _AutoState.pollingBrowser ? null : _browserPoll,
              ),
              if (_auto == _AutoState.pollingBrowser) ...[
                const SizedBox(height: 6),
                _LinkText(
                  text: 'cancel waiting',
                  onTap: _cancelPoll,
                ),
              ],
              if (_auto == _AutoState.needExtension) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: AppTheme.borderRadius,
                    border: AppTheme.border(),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "couldn't read the cookie automatically.\n"
                        "modern Chrome/Brave wrap cookies so only an "
                        "extension can fetch them.",
                        style: AppTheme.mono(
                          size: 10,
                          color: AppColors.textMid,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _PrimaryButton(
                        label: 'load the helper extension',
                        compact: true,
                        onTap: _startExtensionBridge,
                      ),
                    ],
                  ),
                ),
              ],
              if (_auto == _AutoState.awaitingBridge) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: AppTheme.borderRadius,
                    border: AppTheme.border(),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '1. ${chromiumExtensionsHint()}\n'
                        '2. toggle "Developer mode" (top right)\n'
                        '3. click "Load unpacked"\n'
                        '4. pick the folder that just opened',
                        style: AppTheme.mono(
                          size: 10,
                          color: AppColors.textMid,
                          height: 1.7,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AppColors.acid,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'waiting for the extension…',
                            style: AppTheme.mono(
                              size: 10,
                              color: AppColors.textMid,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
            if (_hint != null) ...[
              const SizedBox(height: 10),
              Text(
                _hint!,
                style: AppTheme.mono(size: 10, color: AppColors.acid),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                const Expanded(child: Divider(color: AppColors.border)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'or paste oauth_token',
                    style: AppTheme.mono(size: 10, color: AppColors.textLow),
                  ),
                ),
                const Expanded(child: Divider(color: AppColors.border)),
              ],
            ),
            const SizedBox(height: 14),
            _TokenField(controller: _token),
            const SizedBox(height: 10),
            // На Windows webview-логин лагает/не открывается — ручная вставка
            // токена это основной путь. Помогаем достать его.
            Row(
              children: [
                Pressable(
                  onTap: () => openExternalUrl('https://soundcloud.com'),
                  child: Text(
                    'open soundcloud.com ↗',
                    style: AppTheme.mono(size: 10, color: AppColors.acid),
                  ),
                ),
                const Spacer(),
                Pressable(
                  onTap: () => setState(() => _showHelp = !_showHelp),
                  child: Text(
                    _showHelp ? 'hide help' : 'how to get token?',
                    style: AppTheme.mono(size: 10, color: AppColors.textMid),
                  ),
                ),
              ],
            ),
            if (_showHelp) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: AppTheme.borderRadius,
                  border: AppTheme.border(),
                ),
                child: Text(
                  '1. open soundcloud.com and log in\n'
                  '2. open devtools — F12 (win) / ⌥⌘I (mac)\n'
                  '3. application ▸ cookies ▸ soundcloud.com\n'
                  '4. copy the value of "oauth_token"\n'
                  '5. paste it above and hit save',
                  style: AppTheme.mono(
                    size: 10,
                    color: AppColors.textMid,
                    height: 1.7,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Pressable(
                  onTap: () => Navigator.of(context).pop(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Text(
                      'cancel',
                      style: AppTheme.mono(size: 12, color: AppColors.textMid),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _PrimaryButton(
                  label: 'save',
                  compact: true,
                  onTap: _token.text.trim().isEmpty
                      ? null
                      : () => _done(_token.text),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Per-browser chrome-scheme; Edge/Brave use their own URI for the extensions
/// page. We open the user's default browser via `openExternalUrl` so we don't
/// know which one it is — show all the common options.
String chromiumExtensionsHint() =>
    'open one of: chrome://extensions  /  brave://extensions  /  edge://extensions';

class _TokenField extends StatelessWidget {
  const _TokenField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: AppTheme.borderRadius,
        border: AppTheme.border(),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: TextField(
        controller: controller,
        style: AppTheme.mono(size: 12, color: AppColors.textHi),
        cursorColor: AppColors.acid,
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: '2-XXXXXX…',
          hintStyle: AppTheme.mono(size: 12, color: AppColors.textLow),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    this.onTap,
    this.busy = false,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool busy;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Pressable(
      enabled: enabled,
      onTap: onTap,
      child: Container(
        width: compact ? null : double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 18 : 14,
          vertical: 11,
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? AppColors.acid : AppColors.surface2,
          borderRadius: AppTheme.borderRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy) ...[
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.bg,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: AppTheme.mono(
                size: 12,
                color: enabled ? AppColors.bg : AppColors.textLow,
                weight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Outlined variant of [_PrimaryButton]: same shape and busy spinner, no
/// acid fill. Used for the Tier 2 "sign in via my browser" CTA so the primary
/// WebView path remains visually dominant.
class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.label,
    this.onTap,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Pressable(
      enabled: enabled,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppTheme.borderRadius,
          border: Border.all(
            color: enabled ? AppColors.acid : AppColors.border,
            width: AppTheme.borderWidth,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy) ...[
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.acid,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: AppTheme.mono(
                size: 12,
                color: enabled ? AppColors.acid : AppColors.textLow,
                weight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkText extends StatelessWidget {
  const _LinkText({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Text(
        text,
        style: AppTheme.mono(size: 10, color: AppColors.textMid),
      ),
    );
  }
}
