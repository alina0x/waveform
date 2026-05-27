import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Кэш-менеджер обложек/аватарок для CachedNetworkImage.
///
/// Дефолтный менеджер хранит индекс кэша в sqflite, у которого нет плагина
/// на macOS/desktop (MissingPluginException `getDatabasesPath`) — из-за чего
/// картинки не грузились. [JsonCacheInfoRepository] держит индекс в JSON-файле
/// (через path_provider, который десктоп поддерживает) — без sqflite.
final waveformImageCache = CacheManager(
  Config(
    'waveformImageCache',
    stalePeriod: const Duration(days: 14),
    maxNrOfCacheObjects: 800,
    repo: JsonCacheInfoRepository(databaseName: 'waveformImageCache'),
    fileService: HttpFileService(),
  ),
);
