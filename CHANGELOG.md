# Changelog

All notable changes to Waveform are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-05-28

First demo release for friends. Far from a polished v1.0, but the daily-driver
loop works end-to-end on macOS (Windows / Linux build too, less exercised).

### Added — visual & interaction
- Hero transitions for cover art when navigating cards → track / playlist
  detail.
- Subtle hover fill on every `Pressable` (Apple Finder-like).
- Unified `EmptyState` widget wired into search / library tabs / feed / track
  comments (no more bare blank zones).
- Skeleton loaders for the home screen first paint (replaces the acid
  spinner with a layout-matching placeholder).
- Optimistic +1 / −1 on like and repost counters on the track page; reverts
  if the API write fails.
- Volume scroll-wheel on the player volume icon + mute tooltip with the
  current `xx%`.
- Buffered tier on the mini-waveform (acid at 0.35 alpha between played and
  unplayed bars).
- Ambient album-art backdrop on `/track` and `/playlist` heroes (extracted
  via `palette_generator`, soft top→transparent gradient).

### Added — input & navigation
- TopBar search field doubles as a **⌘K omnibox**: actions
  (settings / logs / likes / shuffle / sign out / clear cache), live
  SoundCloud results (debounced 250 ms), recent queries (persisted), and a
  "search '<q>' →" footer for the full results page. Placeholder shows
  `playing: <artist> — <title>` when empty.
- Global keyboard shortcuts: **Space** play / pause, **← / →** prev / next,
  **⌘/Ctrl + K** or **F** focus omnibox, **⌘/Ctrl + L** open library /
  likes, **⌘/Ctrl + ,** open settings, **⌘/Ctrl + Shift + L** open logs.
- Right-click context menu on track rows (play / like / repost / copy
  link / open on SoundCloud / open artist / open track page).

### Added — player
- Persistent right-side **queue panel** with current-track header,
  drag-handle reorder, and remove buttons. Toggle via the `queue_music`
  icon in the top bar.
- BottomPlayer **collapse mode**: a 44 px bar with mini cover + mono ticker
  + play / next / chevron-up. Toggle via the `expand_more` icon at the right
  edge of the expanded bar.
- **Gapless playback** by default (two-engine architecture in
  `JustAudioEngine` — preloads the next track on the inactive `AudioPlayer`
  and instant-swaps on completion).
- **Crossfade** 0–6 s configurable in `/settings → playback`; 0 = pure
  gapless.
- **OS media keys + now-playing** via `audio_service`: Control Center on
  macOS, SystemMediaTransportControls on Windows, MPRIS on Linux.

### Added — integrations
- **Last.fm scrobbling**: optional, off by default until you fill
  `lastfmApiKey` + `lastfmSharedSecret` in
  `lib/core/lastfm/lastfm_constants.dart`. Once configured: connect via
  `/settings → last.fm`, browser auth flow, scrobbles on ≥50 % played
  OR ≥4 min.
- **Local listening stats** (`/stats`): total plays / unique artists / total
  hours, top 10 artists with progress bars, top genres pills. Aggregated
  from up to ~400 entries of `/me/play-history`.

### Added — release pipeline
- GitHub Actions CI (`flutter analyze` + `flutter test` on every push and
  PR, pinned to Flutter 3.41.0 to match local dev).
- Release workflow on `v*` tags: parallel macOS / Windows / Linux builds.
  macOS is signed with the `Developer ID Application` cert, notarized via
  `xcrun notarytool`, stapled, and packaged as a `.dmg` (no Gatekeeper
  prompts at install for users). Windows / Linux ship as plain `.zip` /
  `.tar.gz` for now.

### Changed
- Library tabs and search → playlists support a global **tiles ↔ list**
  toggle (persisted via the new `PrefsStore`).
- OAuth token persistence moved from `flutter_secure_storage` (didn't
  survive launches on sandboxed macOS without a dev-team signing
  identity) to a small file in `getApplicationSupportDirectory()` —
  inside the per-app sandbox container.

### Known limitations
- **GO+ (subscription) tracks won't play**: they're served as DRM-encrypted
  HLS that `just_audio` can't decode on desktop. They're labelled `🔒 GO+`
  and skipped instead of failing silently.
- **macOS-first**. Windows / Linux build but are less exercised.
- Like / repost API write endpoints (`/users/{me}/track_likes/{id}` and
  `/track_reposts/{id}`) are best-effort — blocked / captcha responses are
  surfaced via a SnackBar with a "verify" action that opens
  soundcloud.com in a webview.
- Listening stats currently look at the most recent ~400 plays — no
  full-history paginator, no time-of-day heatmap (backlog).
- Windows builds are **unsigned** (no EV cert yet); SmartScreen will warn
  the first time.

[0.1.0]: https://github.com/alina0x/waveform/releases/tag/v0.1.0
