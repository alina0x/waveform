import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';

/// Waveform во всю ширину: прослушанная часть — acid orange,
/// непрослушанная — waveDim. Клик/драг по дорожке вызывает [onSeek] (доля 0..1).
class WaveformView extends StatelessWidget {
  const WaveformView({
    super.key,
    required this.bars,
    this.progress = 0,
    this.onSeek,
    this.height = 64,
    this.markers = const [],
  });

  final List<double> bars;
  final double progress;
  final ValueChanged<double>? onSeek;
  final double height;

  /// Доли (0..1) для маркеров комментариев над дорожкой.
  final List<double> markers;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, c) {
          void seekAt(Offset local) =>
              onSeek?.call((local.dx / c.maxWidth).clamp(0.0, 1.0));

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: onSeek == null ? null : (d) => seekAt(d.localPosition),
            onHorizontalDragUpdate:
                onSeek == null ? null : (d) => seekAt(d.localPosition),
            child: CustomPaint(
              size: Size(c.maxWidth, height),
              painter: _WaveformPainter(
                  bars: bars, progress: progress, markers: markers),
            ),
          );
        },
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.bars,
    required this.progress,
    this.markers = const [],
  });

  final List<double> bars;
  final double progress;
  final List<double> markers;

  static const double _gap = 1.5;
  static const double _minBar = 2;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;

    // Подгоняем число баров под ширину, чтобы не сжимать в кашу.
    final maxBars = (size.width / (_minBar + _gap)).floor().clamp(1, bars.length);
    final step = bars.length / maxBars;
    final barWidth =
        (size.width - _gap * (maxBars - 1)) / maxBars;

    final mid = size.height / 2;
    final playedX = size.width * progress;

    final played = Paint()..color = AppColors.acid;
    final dim = Paint()..color = AppColors.waveDim;

    for (var i = 0; i < maxBars; i++) {
      final amp = bars[(i * step).floor()];
      final h = (amp * size.height).clamp(2.0, size.height);
      final x = i * (barWidth + _gap);
      final rect = Rect.fromLTWH(x, mid - h / 2, barWidth, h);
      // Бар оранжевый, если его центр левее курсора воспроизведения.
      canvas.drawRect(rect, x + barWidth / 2 <= playedX ? played : dim);
    }

    // Маркеры комментариев — маленькие lime-точки над дорожкой.
    final marker = Paint()..color = AppColors.lime;
    for (final f in markers) {
      canvas.drawCircle(Offset(size.width * f, 3), 2.2, marker);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress || old.bars != bars || old.markers != markers;
}
