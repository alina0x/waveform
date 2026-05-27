import 'dart:ui';

import 'package:flutter/material.dart';

/// macOS-vibrancy: размывает контент под баром. Внутрь кладём полупрозрачный
/// бар (TopBar / BottomPlayer) — он даёт цвет и hairline-границу поверх блюра.
class FrostedBar extends StatelessWidget {
  const FrostedBar({super.key, required this.child, this.sigma = 18});

  final Widget child;
  final double sigma;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: child,
      ),
    );
  }
}
