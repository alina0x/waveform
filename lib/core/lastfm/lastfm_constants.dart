/// Last.fm API credentials. Это **публичные** ключи приложения (не секреты для
/// конечного пользователя), хардкодим как делают yt-dlp, Quod Libet и другие
/// OSS-клиенты. Зарегистрируй Waveform на:
///   https://www.last.fm/api/account/create
/// и подставь обе константы. Пустые значения → scrobbling выключен (no-op).
const String lastfmApiKey = '';
const String lastfmSharedSecret = '';

/// REST endpoint Last.fm.
const String lastfmApiRoot = 'https://ws.audioscrobbler.com/2.0/';

/// Готов ли клиент пытаться запросы (есть ли ключи).
bool get lastfmConfigured =>
    lastfmApiKey.isNotEmpty && lastfmSharedSecret.isNotEmpty;
