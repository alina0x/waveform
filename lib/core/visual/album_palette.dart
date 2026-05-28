import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

/// Доминантный цвет обложки трека/плейлиста. Используется как мягкая ambient-
/// подложка под hero-блоком (как в Apple Music/Spotify). Возвращает null если
/// URL пуст или извлечение упало (offline-обложка, неподдерживаемый формат).
final albumPaletteProvider =
    FutureProvider.family<Color?, String?>((ref, imageUrl) async {
  if (imageUrl == null || imageUrl.isEmpty) return null;
  try {
    final pal = await PaletteGenerator.fromImageProvider(
      NetworkImage(imageUrl),
      size: const Size(80, 80),
      maximumColorCount: 8,
    );
    return pal.dominantColor?.color ??
        pal.vibrantColor?.color ??
        pal.mutedColor?.color;
  } catch (_) {
    return null;
  }
});
