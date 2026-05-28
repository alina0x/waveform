import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/visual/album_palette.dart';

/// Мягкий ambient-фон под hero-блоком: вертикальный градиент из доминантного
/// цвета обложки в transparent. Без обложки (offline / 404 палитры) — child
/// рендерится без фона.
class AmbientBackdrop extends ConsumerWidget {
  const AmbientBackdrop({
    super.key,
    required this.imageUrl,
    required this.child,
    this.alpha = 0.22,
  });

  final String? imageUrl;
  final Widget child;
  final double alpha;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(albumPaletteProvider(imageUrl));
    final color = palette.asData?.value;
    return Stack(
      children: [
        if (color != null)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 320),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      color.withValues(alpha: alpha),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        child,
      ],
    );
  }
}
