import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../core/cache/image_cache.dart';

/// Ambient hero-фон: ОБЛОЖКА растянутая на ширину, сильно размытая и
/// затемнённая. Снизу плавно сходит к `AppColors.bg`. Безопасно при null/
/// невалидном URL — просто рендерит child без фона.
///
/// Заменяет старый palette_generator-градиент (он был слишком слабый).
class AmbientBackdrop extends StatelessWidget {
  const AmbientBackdrop({
    super.key,
    required this.imageUrl,
    required this.child,
    this.height = 360,
    this.blurSigma = 60,
  });

  final String? imageUrl;
  final Widget child;

  /// Высота backdrop'а в пикселях (после неё фон полностью сходит к bg).
  final double height;

  /// Силa размытия.
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) return child;
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: height,
          child: IgnorePointer(
            child: ClipRect(
              child: Stack(
                children: [
                  // Сама обложка — растянутая на ширину, BoxFit.cover.
                  Positioned.fill(
                    child: CachedNetworkImage(
                      imageUrl: url,
                      cacheManager: waveformImageCache,
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 220),
                      placeholder: (_, _) => const SizedBox.shrink(),
                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                      imageBuilder: (_, provider) => ImageFiltered(
                        imageFilter: ImageFilter.blur(
                            sigmaX: blurSigma, sigmaY: blurSigma),
                        child: Image(image: provider, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                  // Затемнение (равномерное).
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.55),
                    ),
                  ),
                  // Градиент в bg к низу — чтобы фон плавно сошёл в страницу.
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            AppColors.bg.withValues(alpha: 0.4),
                            AppColors.bg,
                          ],
                          stops: const [0.0, 0.6, 1.0],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
