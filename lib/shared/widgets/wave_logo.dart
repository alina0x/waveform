import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';

/// Лого Waveform: 5 вертикальных оранжевых баров разной высоты.
class WaveLogo extends StatelessWidget {
  const WaveLogo({super.key, this.size = 18, this.color = AppColors.acid});

  final double size;
  final Color color;

  // Относительные высоты баров (0..1).
  static const _heights = [0.5, 1.0, 0.35, 0.8, 0.6];

  @override
  Widget build(BuildContext context) {
    final barWidth = size / 9;
    return SizedBox(
      width: size,
      height: size,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final h in _heights)
            Container(width: barWidth, height: size * h, color: color),
        ],
      ),
    );
  }
}
