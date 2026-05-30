import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/colors.dart';
import '../../core/api/providers.dart';
import '../../core/api/soundcloud_auth.dart';
import '../../core/api/webview_login.dart';
import '../../shared/url_share.dart';
import '../../shared/widgets/pressable.dart';

Future<void> showLoginDialog(BuildContext context) => showDialog(
  context: context,
  barrierColor: AppColors.bg.withValues(alpha: 0.6),
  builder: (_) => const _LoginDialog(),
);

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

  @override
  void initState() {
    super.initState();
    _token.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  void _done(String token) {
    ref.read(authControllerProvider.notifier).signIn(token.trim());
    Navigator.of(context).pop();
  }

  Future<void> _webviewLogin() async {
    setState(() {
      _busy = true;
      _hint = null;
    });
    try {
      if (!await WebviewLogin.available()) {
        setState(() => _hint = 'webview unavailable — paste token below');
        return;
      }
      final api = ref.read(soundcloudApiProvider);
      final token = await WebviewLogin.signIn(validate: api.verifyToken);
      if (token != null && token.isNotEmpty) {
        _done(token);
        return;
      }
      setState(() => _hint = "couldn't read token — paste it below");
    } catch (e) {
      setState(() => _hint = 'login failed — paste token below');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
            _PrimaryButton(
              label: _busy
                  ? 'waiting for sign-in…'
                  : 'continue with SoundCloud',
              busy: _busy,
              onTap: _busy ? null : _webviewLogin,
            ),
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
