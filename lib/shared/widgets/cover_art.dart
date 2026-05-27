import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/colors.dart';
import '../../core/cache/image_cache.dart';

/// Обложка трека/подборки. Если есть [imageUrl] — грузим реальный арт
/// (cached_network_image); placeholder/ошибка → детерминированная процедурная
/// обложка из seed (она же — offline-режим на моках).
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    required this.seed,
    this.imageUrl,
    this.size = 160,
    this.circular = false,
  });

  final String seed;
  final String? imageUrl;
  final double size;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final h = seed.hashCode;
    // Приглушённые тёмные тона — обложка не должна спорить с acid orange.
    final base = HSLColor.fromAHSL(1, (h % 360).toDouble(), 0.18, 0.16).toColor();
    final tint = HSLColor.fromAHSL(1, ((h >> 3) % 360).toDouble(), 0.22, 0.24)
        .toColor();

    final procedural = CustomPaint(
      size: Size(size, size),
      painter: _CoverPainter(seed: h, base: base, tint: tint),
    );

    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    final Widget content = hasImage
        ? CachedNetworkImage(
            imageUrl: imageUrl!,
            cacheManager: waveformImageCache,
            width: size,
            height: size,
            fit: BoxFit.cover,
            fadeInDuration: AppTheme.motion,
            placeholder: (_, _) => procedural,
            errorWidget: (_, _, _) => procedural,
          )
        : procedural;

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular ? null : AppTheme.borderRadius,
        border: AppTheme.border(AppColors.borderDim),
      ),
      child: content,
    );
  }
}

class _CoverPainter extends CustomPainter {
  _CoverPainter({required this.seed, required this.base, required this.tint});

  final int seed;
  final Color base;
  final Color tint;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, tint],
        ).createShader(rect),
    );

    // Несколько диагональных полос — лёгкая текстура «релиза».
    final stripe = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..strokeWidth = 1;
    final offset = (seed % 20) - 10;
    for (var x = -size.height + offset.toDouble();
        x < size.width;
        x += 14) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), stripe);
    }
  }

  @override
  bool shouldRepaint(_CoverPainter old) => old.seed != seed;
}
