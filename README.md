# Waveform

[![CI](https://github.com/alina0x/waveform/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/alina0x/waveform/actions/workflows/ci.yml)

A minimal, cross-platform **desktop SoundCloud client** built with Flutter — for macOS, Windows, and Linux.

Aesthetic: minimalism with light web3 accents. Closer to the canonical SoundCloud layout, but darker and quieter.

> **Status: early work-in-progress.** Waveform is usable for everyday browsing and playback, but it is **far from a polished release** — APIs are unofficial, some flows are unverified, and rough edges remain. Treat it as a development preview, not a finished product.

---

## What works today

- **Live SoundCloud data** via the internal `api-v2` (no mock data in the shipping app).
- **Per-user login** through SoundCloud's real sign-in page in an embedded WebView — your password is never seen by the app; only the session token is captured and persisted locally in the app's sandboxed data directory.
- **Real audio playback** of HLS streams through [`just_audio`] (native AVPlayer on macOS).
- **Screens:** Home (your stream + curated shelves), Feed, Library (likes / playlists / albums / stations / following / history), Search (tracks / people / playlists), Track page (waveform + comments with timecodes + related), Artist page, Playlist page.
- **Player:** play/pause, next/previous, true full-coverage shuffle, repeat, scrubbing on the waveform, volume, and like (with optimistic state synced to your account).
- **Right rail:** profile, real collection shortcuts (likes / playlists / following), recent likes, listening history.
- **Logging:** in-app [Talker] log screen (`/logs`) with Riverpod + Dio integration.

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
