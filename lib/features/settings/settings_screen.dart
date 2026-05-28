import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/colors.dart';
import '../../core/api/feeds.dart';
import '../../core/api/soundcloud_auth.dart';
import '../../core/cache/image_cache.dart';
import '../../shared/widgets/cover_art.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/section_header.dart';
import '../../shared/widgets/view_toggle.dart';
import '../auth/login_dialog.dart';

/// Версия отображается в секции About; обновлять руками синхронно с pubspec.yaml.
const _kAppVersion = '0.1.0';
const _kRepoUrl = 'https://github.com/alina0x/waveform';

/// Экран настроек. Сейчас покрывает то, что реально реализовано: аккаунт,
/// вид списков, кэш обложек, выход на логи и about. Тема / Last.fm / качество
/// стрима появятся, когда сама фича в коде заведётся.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppTheme.pagePad,
              AppTheme.topBarHeight + 20, AppTheme.pagePad, AppTheme.playerHeight + 32),
          children: const [
            _Back(),
            SizedBox(height: 16),
            _Title(),
            SizedBox(height: 28),
            _AccountSection(),
            SizedBox(height: 28),
            _ViewSection(),
            SizedBox(height: 28),
            _CacheSection(),
            SizedBox(height: 28),
            _LogsSection(),
            SizedBox(height: 28),
            _AboutSection(),
          ],
        ),
      ),
    );
  }
}

class _Back extends StatelessWidget {
  const _Back();
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Pressable(
        onTap: () => context.canPop() ? context.pop() : context.go('/'),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chevron_left, size: 18, color: AppColors.textMid),
            Text('back', style: AppTheme.mono(size: 12, color: AppColors.textMid)),
          ],
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title();
  @override
  Widget build(BuildContext context) {
    return const Text('settings',
        style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: AppColors.textHi));
  }
}

class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authed = ref.watch(authControllerProvider).isAuthenticated;
    final me = ref.watch(railProvider).asData?.value.me;
    return _Section(
      title: 'account',
      child: authed
          ? Row(
              children: [
                CoverArt(
                    seed: 'artist-${me?.handle ?? 'me'}',
                    imageUrl: me?.avatarUrl,
                    size: 44,
                    circular: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(me?.name ?? 'logged in',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textHi)),
                      const SizedBox(height: 3),
                      Text('@${me?.handle ?? ''}',
                          style: AppTheme.mono(
                              size: 11, color: AppColors.textMid)),
                    ],
                  ),
                ),
                _Button(
                  label: 'sign out',
                  onTap: () =>
                      ref.read(authControllerProvider.notifier).signOut(),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Text('not signed in',
                      style:
                          AppTheme.mono(size: 12, color: AppColors.textMid)),
                ),
                _Button(label: 'sign in', onTap: () => showLoginDialog(context)),
              ],
            ),
    );
  }
}

class _ViewSection extends StatelessWidget {
  const _ViewSection();
  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'view',
      child: Row(
        children: [
          Expanded(
            child: Text('library & search layout',
                style: AppTheme.mono(size: 12, color: AppColors.textMid)),
          ),
          const ViewToggle(),
        ],
      ),
    );
  }
}

class _CacheSection extends StatefulWidget {
  const _CacheSection();
  @override
  State<_CacheSection> createState() => _CacheSectionState();
}

class _CacheSectionState extends State<_CacheSection> {
  bool _busy = false;

  Future<void> _clear() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await waveformImageCache.emptyCache();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surface2,
          content: Text('cover cache cleared',
              style: AppTheme.mono(size: 12, color: AppColors.textHi)),
        ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'cache',
      child: Row(
        children: [
          Expanded(
            child: Text('clear downloaded cover art',
                style: AppTheme.mono(size: 12, color: AppColors.textMid)),
          ),
          _Button(label: _busy ? 'clearing…' : 'clear', onTap: _clear),
        ],
      ),
    );
  }
}

class _LogsSection extends StatelessWidget {
  const _LogsSection();
  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'logs',
      child: Row(
        children: [
          Expanded(
            child: Text('in-app Talker log screen',
                style: AppTheme.mono(size: 12, color: AppColors.textMid)),
          ),
          _Button(label: 'open', onTap: () => context.push('/logs')),
        ],
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();
  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'about',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('version',
                    style: AppTheme.mono(size: 12, color: AppColors.textMid)),
              ),
              Text(_kAppVersion,
                  style: AppTheme.mono(
                      size: 12,
                      color: AppColors.textHi,
                      weight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text('source code',
                    style: AppTheme.mono(size: 12, color: AppColors.textMid)),
              ),
              _Button(label: 'open ↗', onTap: () => _openUrl(_kRepoUrl)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Открывает URL в системном браузере без url_launcher (нативные shell-команды).
Future<void> _openUrl(String url) async {
  try {
    if (Platform.isMacOS) {
      await Process.run('open', [url]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', url]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [url]);
    }
  } catch (_) {}
}

/// Карточка-секция: моно-заголовок + содержимое в кадре с тонким бордером.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title),
        const SizedBox(height: AppTheme.headerGap),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppTheme.borderRadius,
            border: AppTheme.border(),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: AppTheme.borderRadius,
          border: AppTheme.border(),
        ),
        child: Text(label,
            style: AppTheme.mono(
                size: 11,
                color: AppColors.textHi,
                weight: FontWeight.w500)),
      ),
    );
  }
}
