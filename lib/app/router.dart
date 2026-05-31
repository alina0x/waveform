import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/artist/artist_screen.dart';
import '../features/daily_drops/daily_drops_screen.dart';
import '../features/debug/logs_screen.dart';
import '../features/feed/feed_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/playlist/playlist_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/stats/stats_screen.dart';
import '../features/track/track_screen.dart';
import 'app_shell.dart';

/// Мягкий переход экрана: fade + лёгкий подъём (apple-like).
CustomTransitionPage<void> _page(Widget child) {
  return CustomTransitionPage<void>(
    child: child,
    transitionDuration: const Duration(milliseconds: 240),
    reverseTransitionDuration: const Duration(milliseconds: 160),
    transitionsBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.015),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

final appRouter = GoRouter(
  // START позволяет открыть приложение сразу на нужном экране (deep-link / скриншоты).
  initialLocation: const String.fromEnvironment('START', defaultValue: '/'),
  routes: [
    ShellRoute(
      builder: (context, state, child) =>
          AppShell(location: state.uri.path, child: child),
      routes: [
        GoRoute(path: '/', pageBuilder: (c, s) => _page(const HomeScreen())),
        GoRoute(
          path: '/feed',
          pageBuilder: (c, s) => _page(const FeedScreen()),
        ),
        GoRoute(
          path: '/daily',
          pageBuilder: (c, s) => _page(const DailyDropsScreen()),
        ),
        GoRoute(
          // `/likes` and `/history` are first-class top-bar destinations
          // that drop the user directly into the matching Library tab —
          // saves a click vs `/library?tab=…` and gives each tab a stable
          // URL the nav bar can highlight unambiguously.
          path: '/likes',
          pageBuilder: (c, s) => _page(const LibraryScreen(initialTab: 'likes')),
        ),
        GoRoute(
          path: '/history',
          pageBuilder: (c, s) =>
              _page(const LibraryScreen(initialTab: 'history')),
        ),
        GoRoute(
          path: '/library',
          pageBuilder: (c, s) =>
              _page(LibraryScreen(initialTab: s.uri.queryParameters['tab'])),
        ),
        GoRoute(
          path: '/track/:id',
          pageBuilder: (c, s) =>
              _page(TrackScreen(trackId: s.pathParameters['id']!)),
        ),
        GoRoute(
          path: '/artist/:handle',
          pageBuilder: (c, s) => _page(
            ArtistScreen(
              handle: Uri.decodeComponent(s.pathParameters['handle']!),
            ),
          ),
        ),
        GoRoute(
          path: '/search',
          pageBuilder: (c, s) =>
              _page(SearchScreen(query: s.uri.queryParameters['q'] ?? '')),
        ),
        GoRoute(
          path: '/playlist/:id',
          pageBuilder: (c, s) =>
              _page(PlaylistScreen(id: s.pathParameters['id']!)),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (c, s) => _page(const SettingsScreen()),
        ),
        GoRoute(
          path: '/stats',
          pageBuilder: (c, s) => _page(const StatsScreen()),
        ),
      ],
    ),
    // Экран логов — вне shell (на весь экран, без TopBar/плеера).
    GoRoute(path: '/logs', builder: (c, s) => const LogsScreen()),
  ],
);
