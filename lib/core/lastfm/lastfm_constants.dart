/// Last.fm API credentials.
///
/// **Никогда не комитить в исходники.** Поставляются через `--dart-define`
/// на сборке, а реальные значения держим в GitHub Actions secrets
/// (`LASTFM_API_KEY`, `LASTFM_SHARED_SECRET`).
///
/// Локально для тестирования scrobbling'а:
/// ```
/// flutter run --dart-define=LASTFM_API_KEY=xxxx \
///             --dart-define=LASTFM_SHARED_SECRET=yyyy
/// ```
///
/// Без значений `lastfmConfigured == false` и весь scrobbler subsystem
/// тихо no-op'ит. Settings показывает «not configured».
///
/// Регистрация на: https://www.last.fm/api/account/create.
const String lastfmApiKey =
    String.fromEnvironment('LASTFM_API_KEY', defaultValue: '');
const String lastfmSharedSecret =
    String.fromEnvironment('LASTFM_SHARED_SECRET', defaultValue: '');

/// REST endpoint Last.fm.
const String lastfmApiRoot = 'https://ws.audioscrobbler.com/2.0/';

/// Готов ли клиент пытаться запросы (есть ли ключи).
bool get lastfmConfigured =>
    lastfmApiKey.isNotEmpty && lastfmSharedSecret.isNotEmpty;
