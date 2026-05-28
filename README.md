# Waveform

[![CI](https://github.com/alina0x/waveform/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/alina0x/waveform/actions/workflows/ci.yml)

A minimal, cross-platform **desktop SoundCloud client** built with Flutter — for macOS, Windows, and Linux.

Aesthetic: minimalism with light web3 accents. Closer to the canonical SoundCloud layout, but darker and quieter.

> **Status: early demo release (v0.1.0).** Waveform is usable as a daily-driver player but still far from a polished v1 — APIs are unofficial, some flows are best-effort, and rough edges remain. The full change log is in [`CHANGELOG.md`](CHANGELOG.md).

## Install

Pre-built binaries are attached to every GitHub release.

### macOS
1. Download `waveform-macos-vX.Y.Z.dmg` from the [latest release](https://github.com/alina0x/waveform/releases/latest).
2. Open the DMG and drag `waveform_app` to your `Applications` folder.
3. Double-click. The app is signed with Apple Developer ID and notarized, so it opens without Gatekeeper prompts.

### Windows
1. Download `waveform-windows-vX.Y.Z.zip` and unzip.
2. Run `waveform_app.exe`. SmartScreen will say "Unknown publisher" the first time (no EV signing cert yet) — click **More info → Run anyway**.

### Linux
1. Download `waveform-linux-vX.Y.Z.tar.gz`.
2. `tar xzf` it and run `./waveform_app`.

---

## What works today

- **Live SoundCloud data** via the internal `api-v2` (no mock data in the shipping app).
- **Per-user login** through SoundCloud's real sign-in page in an embedded WebView — your password is never seen by the app; only the session token is captured and persisted locally in the app's sandboxed data directory.
- **Real audio playback** of HLS streams via [`just_audio`] (native AVPlayer on macOS), with **gapless** and configurable **crossfade** (0–6 s) between tracks.
- **OS media keys + now-playing** card via `audio_service` (Control Center on macOS, SystemMediaTransportControls on Windows, MPRIS on Linux).
- **Screens:** Home (your stream + curated shelves), Feed, Library (likes / playlists / albums / stations / following / history), Search (tracks / people / playlists), Track page (waveform + comments with timecodes + related), Artist page, Playlist page, Settings, **Stats** (top artists, top genres, totals from your play-history).
- **⌘K omnibox**: the top-bar search field doubles as a command palette. Type "settings", "logs", "likes", "shuffle", "sign out" to run actions; type any query for live SoundCloud results; Enter goes to the full search page. Recent queries persist.
- **Global keyboard shortcuts**: Space play/pause; ← / → prev/next; ⌘/Ctrl + K or F focus omnibox; ⌘/Ctrl + L likes; ⌘/Ctrl + , settings; ⌘/Ctrl + Shift + L logs.
- **Right-click context menus** on tracks (play / like / repost / copy link / open on SoundCloud / open artist).
- **Persistent queue panel** with drag-reorder + remove (toggle via the queue icon in the top bar). True full-coverage shuffle within the loaded queue, plus a one-shot "shuffle all" on the playlist screen that paginates the full set first.
- **Collapse mode** on the bottom player (44 px mini bar).
- **Tiles ↔ list** view toggle (persisted), available in Library and Search.
- **Hero transitions** on cover art when navigating cards → detail; subtle **hover fill** on every interactive element; **ambient album-art backdrop** behind hero blocks (via `palette_generator`); **skeleton loaders** on Home first paint.
- **Optional Last.fm scrobbling** (off until configured — see [`lib/core/lastfm/lastfm_constants.dart`](lib/core/lastfm/lastfm_constants.dart)).
- **In-app log screen** at `/logs` powered by [Talker] (Riverpod + Dio integration).

## Design

Dark theme by default (light theme planned). Brutalist details: 3px radii, 0.5px borders.

| Token | Value | Use |
|-------|-------|-----|
| `bg` / `surface` / `surface2` | `#0A0A0A` / `#111111` / `#1A1A1A` | backgrounds |
| `textHi` / `textMid` / `textLow` | `#F5F5F5` / `#888888` / `#555555` | text |
| `acid` | `#FF5500` | active elements only (SoundCloud orange) |
| `lime` | `#C6FF00` | web3 markers (minted / owned) |

Typography: **Inter** for text/headings, **JetBrains Mono** for all numbers, timecodes, and technical labels.

## Stack

Flutter + Dart 3.11. Key packages: `flutter_riverpod` (state), `go_router` (navigation), `just_audio` (playback), `dio` (HTTP), `path_provider` (token + cache paths), `cached_network_image`, `google_fonts`, `talker_flutter` (logging).

## Project structure

```
lib/
├── app/        # theme, router, shell
├── core/
│   ├── api/    # SoundCloud api-v2 client, DTOs, mappers, auth, liked-tracks
│   ├── audio/  # just_audio engine behind an interface
│   ├── cache/  # image cache (JSON-backed; no sqflite on desktop)
│   └── log/    # Talker
├── features/   # auth, home, feed, library, search, track, artist, playlist, player, debug
└── shared/     # models, reusable widgets, formatting helpers
```

Feature-first layout. State via Riverpod, navigation via go_router. All numerics are rendered through an `AppTheme.mono()` helper; acid orange is used sparingly (active elements only).

## Getting started

Prerequisites: a recent [Flutter](https://docs.flutter.dev/get-started/install) SDK with desktop support enabled.

```bash
flutter pub get
flutter run -d macos      # or -d windows / -d linux
```

Run against built-in mock data (offline, no network or login):

```bash
flutter run -d macos --dart-define=MOCK=true
```

Run tests and static analysis:

```bash
flutter test
flutter analyze
```

## How data & auth work

- Waveform talks to SoundCloud's **undocumented `api-v2`**. The app key (`client_id`) is **scraped from soundcloud.com at runtime** — nothing is shipped or hardcoded.
- Personal data requires logging in with **your own SoundCloud account** via the WebView flow. The OAuth token is written to a file inside the app's sandboxed support directory (`getApplicationSupportDirectory()`); anonymous endpoints never carry it.
- Personal collections use `/users/{id}/…` (the `/me/…` equivalents 404 in api-v2).

## Known limitations

- **DRM tracks won't play.** SoundCloud increasingly serves encrypted HLS (`cbc-/ctr-encrypted-hls`), which the desktop audio engine can't decode. Such tracks are skipped — playing them would require Widevine/EME support that `just_audio` doesn't provide on desktop.
- **macOS-first.** Windows/Linux build but are less exercised.
- **Like-write is unverified** against a wide range of accounts; blocked writes (e.g. behind a VPN / captcha challenge) are surfaced in the UI but may not always recover.
- **Official OAuth 2.1 + PKCE** is not used — SoundCloud's developer app registration has been effectively closed for years, so the WebView token flow stands in for it.

## Roadmap

- OS media controls (`audio_service`: now-playing, media keys)
- Official OAuth 2.1 + PKCE (if registration reopens)
- Settings screen (theme, account, stream quality, cache, logs)
- Optional Last.fm scrobbling
- Full-collection true shuffle (paginate the whole collection before shuffling)
- Light theme
- Web3: real wallet connection via WalletConnect (currently visual accents only)

## Disclaimer

This is an **unofficial** client and is **not affiliated with, endorsed by, or connected to SoundCloud**. It uses an undocumented internal API; use of that API may be against SoundCloud's Terms of Service. This project is provided for **educational and personal use** — use it with your own account and at your own risk. SoundCloud, the SoundCloud logo, and related marks are trademarks of their respective owners.

## License

**Not licensed yet.** Until a `LICENSE` file is added, all rights are reserved. A license will be chosen and added later.

[`just_audio`]: https://pub.dev/packages/just_audio
[Talker]: https://pub.dev/packages/talker_flutter
