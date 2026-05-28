import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../core/cache/image_cache.dart';

/// Полноширинный hero-баннер с **обложкой как фоном**: cover растянутая на
/// весь экран, сильно blur + dim, снизу плавно сходит в `AppColors.bg`.
///
/// Это просто визуальный слой — без child. Кладётся в Stack страницы как
/// Positioned(top:0, left:0, right:0), контент рендерится поверх.
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({
    super.key,
    required this.imageUrl,
    this.height = 440,
    this.blurSigma = 80,
    this.dimAlpha = 0.55,
  });

  final String? imageUrl;
  final double height;
  final double blurSigma;
  final double dimAlpha;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) {
      return SizedBox(height: height);
    }
    return IgnorePointer(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: ClipRect(
          child: Stack(
            children: [
              // 1) Обложка — full-cover на всю ширину окна.
              Positioned.fill(
                child: CachedNetworkImage(
                  imageUrl: url,
                  cacheManager: waveformImageCache,
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 280),
                  placeholder: (_, _) => const SizedBox.shrink(),
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                  imageBuilder: (_, provider) => ImageFiltered(
                    imageFilter: ImageFilter.blur(
                        sigmaX: blurSigma, sigmaY: blurSigma),
                    child: Image(image: provider, fit: BoxFit.cover),
                  ),
                ),
              ),
              // 2) Затемнение поверх (равномерное).
              Positioned.fill(
                child: Container(
                    color: Colors.black.withValues(alpha: dimAlpha)),
              ),
              // 3) Градиент от transparent сверху → bg снизу: плавный
              //    переход в обычный фон страницы.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        AppColors.bg.withValues(alpha: 0.5),
                        AppColors.bg,
                      ],
                      stops: const [0.0, 0.65, 1.0],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
