# Waveform — minimal SoundCloud client

## Что это
Кроссплатформенный десктопный SoundCloud-клиент на Flutter для macOS, Windows, Linux.
Эстетика: минимализм + лёгкие web3-акценты, ближе к каноничному SoundCloud, но темнее и тише.

## Дизайн-контракт

**Тема:** тёмная по умолчанию (светлую добавим позже).

**Палитра:**
- bg `#0A0A0A`, surface `#111111`, surface2 `#1A1A1A`
- border `#2A2A2A`, borderDim `#1A1A1A`, waveDim `#3A3A3A`
- textHi `#F5F5F5`, textMid `#888888`, textLow `#555555`
- acid `#FF5500` (SoundCloud orange — только активные элементы)
- lime `#C6FF00` (web3-маркеры: minted, owned)

**Типографика:**
- Inter — основной текст, заголовки
- JetBrains Mono — все числа, тайм-коды, адреса кошельков, технические метки

**Структура канона SoundCloud:**
- Обложка трека 160×160 слева
- Waveform во всю ширину карточки справа от обложки
- Метаданные (лайки, репосты, длительность) снизу моно-шрифтом
- Активный (играющий) waveform — оранжевые бары для прослушанной части, `waveDim` для непрослушанной
- Радиусы 3px (брутальные углы), borders 0.5px

**Лого:** 5 вертикальных оранжевых баров разной высоты (стилизованная waveform).

## Стек

```yaml
dependencies:
  flutter_riverpod: ^2.5.1
  go_router: ^14.2.0
  google_fonts: ^6.2.1
  just_audio: ^0.9.39
  audio_service: ^0.18.13
  cached_network_image: ^3.3.1
  dio: ^5.4.3
  path_provider: ^2.1.5
```

## Структура

```
lib/
├── main.dart
├── app/
│   ├── app.dart
│   ├── theme/{colors.dart, app_theme.dart}
│   └── router.dart
├── core/
│   ├── api/        # SoundCloud client, OAuth 2.1 + PKCE
│   ├── audio/      # just_audio + audio_service
│   └── storage/    # file-based token store (path_provider, sandboxed)
├── features/
│   ├── auth/
│   ├── home/       # stream/feed
│   ├── search/
│   ├── track/
│   ├── library/
│   └── player/     # mini + full
└── shared/widgets/ # переиспользуемые компоненты
```

## Реальность API
- Регистрация SoundCloud API требует подписки Artist Pro
- OAuth 2.1 с обязательным PKCE
- Стримы отдаются как HLS — `just_audio` поддерживает
- На время разработки используем моки

## Web3
- Пока только визуальные элементы: адрес кошелька в шапке, бейдж `◆ minted` (lime) на трек-картах
- Реальное подключение кошелька через WalletConnect v2 — позже, опционально

## Дорожная карта
1. ✅ Дизайн-направление и название
2. ✅ Дизайн-система в Dart (colors, theme, mono helper, токены отступов)
3. ✅ Экраны на моках: shell с навигацией Home/Feed/Library, TopBar + BottomPlayer (persistent), CustomPainter waveform, карусели подборок, правый рейл
   - Home: from your stream + карусели (more/recently/mixed/albums/stations/liked by/made for you/new crew)
   - Feed: лента waveform-постов с баром действий
   - Library: вкладки overview/likes/playlists/albums/stations/following/history
   - Плеер: shuffle/prev/play/next/repeat, like, скраб по waveform (мок-тикер)
   - Экран трека (/track/:id): hero + waveform с маркерами комментариев, web3-панель владельца, комментарии с таймкодами, related tracks
   - Экран артиста (/artist/:handle): шапка (аватар + моно-счётчики + follow + кошелёк), вкладки, popular tracks + albums/playlists
   - Apple-touch: Pressable (spring press), frosted chrome (BackdropFilter TopBar/Player, контент скроллится под баром), мягкие переходы экранов
4. 🔄 Аудио-плеер:
   - ✅ just_audio: реальное воспроизведение HLS (lib/core/audio/audio_engine.dart за провайдером, PlayerController резолвит transcoding→m3u8 и играет; мок-тикер убран)
   - ⏳ audio_service: медиа-контролы ОС (now-playing, медиа-клавиши)
5. 🔄 Замена моков на реальный API:
   - ✅ api-v2 живой по умолчанию (client_id-скрейп + DTO + мапперы); моки только под `--dart-define=MOCK=true`/тесты
   - ✅ Логин per-user через WebView (oauth_token), персональные ручки и рейл под auth-гейтом
   - ⏳ Официальный OAuth 2.1 + PKCE (если откроют регистрацию)
6. ✅ Поиск: экран `/search?q=` с вкладками tracks/people/playlists (search/tracks|users|playlists), поле в шапке submit→навигация
7. Web3-интеграция (опционально; визуальные плейсхолдеры кошелька убраны до реального WalletConnect)

Сделано вне нумерации: экран плейлиста `/playlist/:id` (карусели главной ведут на него), громкость в плеере, логи Talker.
- **Правый рейл переосмыслен (UX):** убрана подставная секция «artists you should follow»
  и фейковая web3-карточка «7 minted tracks». Вместо них — профиль-карточка (тап → свой
  `/artist`, лёгкий ◆ lime-акцент), три тайла-шортката с реальными счётчиками
  (likes/playlists/following → `/library?tab=…`), превью последних лайков (`see all` →
  likes) и история. Только реальные данные.
- **Liked-state.** `likedTracksProvider` (множество ID лайков из `/users/{id}/track_likes`)
  — единый источник подсветки «liked» в списках (`TrackRow` сердечко) и в плеере. Плеер
  ставит `liked` из множества при `play`, `toggleLike` пишет в API (PUT/DELETE
  `/users/{me}/track_likes/{id}`) оптимистично с откатом. NB: write-эндпоинт не проверен
  на живом аккаунте — при провале деградирует до session-local + лог.
- **Progressive-фолбэк стрима + GO+ detection.** `Track.streamCandidates` несёт
  все транскодинги (HLS → progressive); плеер перебирает их, пока один не
  заиграет. Зашифрованные (`cbc-/ctr-encrypted-hls`) транскодинги отсеиваются
  (just_audio их не играет). GO+ треки определяются по наличию encrypted-
  транскодинга (надёжный сигнал, работает из любого payload) + `policy=='SNIP'`
  / `monetization_model=='SUB_HIGH_TIER'`. В UI: `🔒 GO+` badge в `TrackRow`,
  bottom player, track-detail hero; tap → notice «GO+ only». Любая неудачная
  загрузка триггерит видимое уведомление (AppShell `ref.listen`), не silent skip.
- **Tiles ↔ list переключатель.** `viewModeProvider` + `ViewToggle` + новый
  `CollectionRow` — в library + search/playlists. Персистится в `prefs.json`.
- **Экран /settings.** Account (avatar + sign in/out), view (тогл), cache
  (clear cover cache), logs (→ /logs), about (version + GitHub-link). Иконка-
  шестерёнка в TopBar.
- **Shuffle всей коллекции на плейлисте.** `SoundcloudApi.allPlaylistTracks(id)`
  гидрит весь сет (батчи `/tracks?ids=…`); кнопка «shuffle all» рядом с «play».
- **Track-page actions wired.** Like / repost (новый `repostedTracksProvider`,
  PUT/DELETE `/users/{me}/track_reposts/{id}`) / share (copy permalink) / more
  (popup: copy / open on SoundCloud).
- **File-based token persistence.** `lib/core/storage/token_store.dart` +
  `prefs_store.dart` в `getApplicationSupportDirectory()` (вместо
  `flutter_secure_storage`, который без development-team signing на macOS
  ломал сборку и/или не персистил).

## Идеи / бэклог
- **Last.fm-скробблинг (встроенный).** Своя фишка против web-SoundCloud: при прослушивании
  отправлять `track.updateNowPlaying` + `track.scrobble` в Last.fm (scrobble после ~50% трека
  или 4 минут — по правилам Last.fm). Нужен ключ Last.fm API + auth-токен пользователя
  (`auth.getMobileSession`/web-flow), настройка вкл/выкл в профиле. Скробблер слушает
  `PlayerController` (трек сменился / достиг порога). Хранить креды в локальном
  файловом сторе рядом с SoundCloud-токеном (см. `lib/core/storage/`).
- **True-shuffle по всей коллекции (likes).** Для плейлиста сделано
  (`allPlaylistTracks` + `_ShuffleAll`); остаётся «shuffle all likes» —
  пагинация `/users/{id}/track_likes?next_href=…`, UI-точка входа на library/
  likes (кнопка над сеткой).

## Договорённости
- Feature-first структура
- Riverpod для состояния, go_router для навигации
- Все цифры/тайм-коды/адреса — через `AppTheme.mono()` helper
- Acid orange используется скупо: только активные элементы
