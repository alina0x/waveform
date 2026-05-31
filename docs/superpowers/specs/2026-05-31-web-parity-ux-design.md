# Web-parity UX & interaction — design

**Date:** 2026-05-31
**Sub-project:** 1 of 3 in the next release.
Sibling specs (separate cycles): (2) Account reliability — likes/DataDome, Google login popup, Windows webview; (3) macOS audio output / AirPlay picker.

## Goal

Make Waveform feel "seamless" for people who live in web SoundCloud: replicate its
keyboard shortcuts 1:1, plus a handful of interaction niceties (copy-link, trackpad
back, artist-name fidelity, add-next-to-queue). Pure-Dart, no native code, no new
dependencies expected.

## Scope

1. Keyboard shortcuts — full parity with the web SC shortcut sheet.
2. `⌘⇧C` copy-link (Zen-style) with self-copy toast suppression.
3. Share-toast fix — self-initiated copies never trigger the "open in Waveform?" prompt.
4. Artist-from-metadata — show `publisher_metadata.artist` when present.
5. Add-next-to-queue.
6. Trackpad back gesture + back navigation.

Out of scope: anything in sibling specs 2 & 3.

---

## 1. Keyboard shortcuts (1:1 with web SoundCloud)

### Target bindings

| Key | Action | Notes |
|---|---|---|
| `space` | play / pause | exists |
| `→` | seek forward 5s | **new** (was next) |
| `←` | seek backward 5s | **new** (was prev) |
| `shift+→` | next track | was bare `→` |
| `shift+←` | previous track | was bare `←` |
| `shift+↑` | volume up (+0.05) | was bare `↑` |
| `shift+↓` | volume down (−0.05) | was bare `↓` |
| `M` | mute toggle | **new** |
| `L` | like playing track | **new** |
| `shift+L` | repeat toggle | **new** |
| `R` | repost playing track | **new** |
| `0`…`9` | seek to 0%…90% | **new** |
| `P` | navigate to playing track page | **new** |
| `S` | open search (omnibox) | **new** (keep `⌘K`/`⌘F`) |
| `shift+S` | shuffle toggle | **new** |
| `Q` | toggle queue panel | **new** |
| `H` | keyboard-shortcuts overlay | **new** |
| `G` then `L` | go to Likes | **new** chord |
| `G` then `S` | go to Feed | **new** chord |
| `G` then `C` | go to Library | **new** chord |
| `G` then `P` | go to Profile (self `/artist`) | **new** chord |
| `G` then `H` | go to History | **new** chord |

Kept (Waveform extras, no web collision): `⌘K`/`⌘F` omnibox, `⌘,` settings,
`⌘⇧L` logs, `Enter` on `/track/:id` plays the page track.

### Behavioral decisions (confirmed with user — web-parity)

- **Single-letter shortcuts are global but inert while typing.** TextFields consume
  character keys before the global `Shortcuts` widget sees them (same mechanism that
  already protects `space`). So `L`/`R`/`S`/etc. never fire mid-search. The existing
  "shortcuts disabled while omnibox open" guard stays.
- **`G`-chord** uses a custom `ChordController`: pressing `G` arms a ~1200ms window;
  the next matching key resolves the destination, anything else (or timeout) cancels.
  Flutter has no chord activator, so this is bespoke.
- Number/seek/like/repost/repeat shortcuts **no-op when nothing is loaded** (no current
  track), rather than throwing.
- `P` (navigate to playing) routes to `/track/<current.id>`; no-op if nothing playing.

### Components

- **`lib/shared/intents.dart`** — add Intents: `SeekForwardIntent`, `SeekBackwardIntent`,
  `LikePlayingIntent`, `RepeatToggleIntent`, `RepostPlayingIntent`, `MuteToggleIntent`,
  `SeekToPercentIntent(int tenth)`, `NavigateToPlayingIntent`, `OpenSearchIntent`,
  `ShuffleToggleIntent`, `ToggleQueueIntent`, `ShowShortcutsIntent`, `CopyLinkIntent`,
  and a single `GoToIntent(GoTarget dest)` for chord destinations
  (`likes|feed|library|profile|history`). `NextTrackIntent`/`PrevTrackIntent`/
  `VolumeUp/DownIntent` already exist and are re-bound (not removed).
- **`lib/shared/chord_controller.dart`** (new) — small stateful helper: `arm()`,
  `resolve(LogicalKeyboardKey) -> GoTarget?`, internal timer to disarm. Owned by
  `_AppShellState`. Exposes whether a chord is currently armed (so the leading `G`
  itself doesn't get swallowed by other handlers).
- **`lib/app/app_shell.dart`** — rewrite `_shortcuts()` for the table above; add the
  new `Actions` entries delegating to `PlayerController` / `GoRouter` / providers; wire
  the `G` key + chord follow-ups through the shell `Focus.onKeyEvent` (chords don't fit
  the `Shortcuts` activator model cleanly, so handle `G`+next at the key-event layer and
  keep single/modified activators in `Shortcuts`).
- **`lib/features/shortcuts/shortcuts_overlay.dart`** (new) — `H` opens a modal listing
  all shortcuts, styled like the omnibox (full-screen `BackdropFilter` blur + dim,
  Esc/click-away to close). Backed by `shortcutsOverlayOpenProvider`
  (`Notifier<bool>`), mirroring `omniboxOpenProvider`. Single source of truth for the
  shortcut list (a `const` table) so the overlay and the bindings can't drift —
  bindings are derived from the same table where practical, or a test asserts parity.
- **`lib/features/player/player_controller.dart`** — add:
  - `seekBy(Duration delta)` — clamp `[0, duration]`, calls `_engine.seek`.
  - `seekToFraction(double)` — already present as `seekFraction`; reuse for `0–9`.
  - mute: `bool muted` in `PlayerState` + `toggleMute()` that stores the pre-mute
    volume and restores it (engine volume → 0 while muted; UI volume value preserved).
  - `playNext(Track)` — see §5.
- Repost-on-playing reuses `repostedTracksProvider.toggle(currentTrackId)` (the existing
  PUT/DELETE path); like reuses `player.toggleLike()`.

### Error handling

- Every shortcut Action guards on null current-track / unmounted context.
- Like/repost over the network degrade exactly as today (optimistic + toast on failure;
  note the DataDome 403 caveat is handled in sibling spec 2, not here).

### Testing

- Widget test: focus the shell, send key events, assert the right `PlayerController` /
  navigation method fired (mock notifier). Cover: bare `→` = seekBy(+5s),
  `shift+→` = next, `shift+↑` = volume up, `3` = seekFraction(0.3), `G`+`L` = go likes,
  `G`+timeout = no nav, `L` while a TextField is focused = **no** like.
- Parity test: every entry in the shortcut-overlay table has a live binding.

---

## 2. `⌘⇧C` copy-link (Zen-style)

`CopyLinkIntent` → resolve the **current context's** permalink:

- If `location` starts with `/track/<id>` → that track's `permalinkUrl`.
- Else if `/artist/<handle>` → that artist's profile URL.
- Else → the currently-playing track's `permalinkUrl` (null-safe; no-op + brief toast
  "Nothing to copy" if neither exists).

Writes to clipboard, calls `clipboardWatcher.markSeen(url)` (see §3), shows a short
"Link copied" toast (≤2s, no action button).

Touch-points: new Intent/Action in `app_shell.dart`; needs the current page's
track/artist permalink — read from the relevant detail provider keyed by the route id.

---

## 3. Share-toast fix

**Root cause:** `ClipboardWatcher` polls the clipboard; any `soundcloud.com` URL emits a
`clipboardLinkProvider` event → AppShell shows "SoundCloud link copied → open in
Waveform". When the user hits share / copy-link, their own copy is detected and
re-prompts immediately.

**Fix:** every self-initiated copy calls `ref.read(clipboardWatcherProvider).markSeen(url)`
immediately after writing the clipboard (`markSeen` already exists and sets `_lastSeen`,
which the poller compares against). Real external copies still prompt.

Touch-points (all copy sites):
- `lib/features/track/track_screen.dart` — share button + "copy link" in the more menu.
- `lib/shared/widgets/track_context_menu.dart` — "copy link".
- new `⌘⇧C` handler (§2).
- any bottom-player / playlist "copy link" path (audit during implementation).

Centralize: a single `copyTrackLink(ref, url)` helper (writes clipboard + markSeen +
toast) so no copy site can forget the `markSeen` step.

---

## 4. Artist-from-metadata

Web shows `publisher_metadata.artist` (the real performing artist) when it differs from
the uploader's username.

- **`lib/core/api/dto/track_dto.dart`** — parse `publisher_metadata.artist` (nullable
  string) into the DTO.
- **`lib/core/api/mappers.dart`** — `Track.artist = publisherArtist?.trim().isNotEmpty
  == true ? publisherArtist : user.username`. `artistPermalink` stays `user.permalink`.
- **`lib/shared/models/track.dart`** — no field change needed; `artist` is display,
  `artistHandle`/`artistPermalink` keep routing to the **uploader** (the only profile
  that resolves). Confirmed with user: name = metadata text, link = uploader.

Testing: DTO test with `publisher_metadata.artist` present (→ used), absent/empty
(→ falls back to username), and routing asserts handle = uploader permalink.

---

## 5. Add-next-to-queue

`PlayerController.playNext(Track t)`: insert `t` immediately after the current track in
`_queue` (vs. `addToQueue` which appends to the end). De-dupe: if `t` already in queue,
move it to the next position. Bump `queueVersion` so the UI re-derives. Respect shuffle:
insert into the active sequence (the same `_activeSeq` accessor that `reorderUpcoming`
uses) so "next" means next in the order the user actually hears.

Wiring:
- `lib/shared/widgets/track_context_menu.dart` — add "Play next" above existing
  "Add to queue".
- `lib/features/track/track_screen.dart` more-menu — add "Play next".

Testing: `playNext` inserts at current+1; duplicate is moved not duplicated;
`upcomingTracks.first` == the just-added track.

---

## 6. Trackpad back gesture + back navigation

Let a two-finger swipe-back (and the standard back affordance) return to the previous
screen — e.g. open a track from Likes, swipe back → Likes.

- Use go_router: `context.pop()` when `context.canPop()`.
- Horizontal swipe-back: wrap page content (in `AppShell`, around `widget.child`) with a
  gesture detector that recognizes a left→right horizontal drag from the left region and
  triggers `pop()` when history exists. On macOS the trackpad two-finger swipe surfaces
  as horizontal scroll/pan; detect via a `Listener` on pan/scroll deltas with a
  threshold, guarded so it never competes with horizontal carousels (only fires from the
  screen's left edge and when `canPop`).

**Known caveat to verify during implementation:** several navigations use `context.go`
(which replaces rather than pushes), so a real back-stack may not always exist. Audit the
nav calls on the Likes→Track path; switch the offending ones to `context.push` so a
poppable history exists, without breaking deep-link/tab routing. If a clean stack can't
be guaranteed for a path, the gesture simply no-ops there (no fake back).

Testing: manual (gesture); unit-test the "pop when canPop, else no-op" decision helper.

---

## Rollout / sequencing within this spec

Order of implementation (each independently verifiable):
1. Artist-from-metadata (isolated data layer).
2. Add-next-to-queue (isolated controller method + menu).
3. Share-toast fix + `copyTrackLink` helper.
4. Keyboard shortcuts overhaul + `H` overlay + `ChordController`.
5. `⌘⇧C` copy-link (depends on 3's helper).
6. Trackpad back gesture (most exploratory; last).

## Open risks

- **Single-letter global shortcuts vs. focus.** Must verify TextFields across all
  screens actually swallow character keys (search field, omnibox, any inline editors).
  Mitigated by the existing `space` precedent, but tested explicitly.
- **Back-stack integrity** (§6 caveat) — may require touching several `context.go` calls.
- **Chord UX** — the ~1200ms window and the leading-`G` swallowing need hands-on tuning.
