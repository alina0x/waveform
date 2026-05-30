import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';

/// Waveform во всю ширину: прослушанная часть — acid orange, буферизированная
/// (но ещё не сыгранная) — приглушённый acid, остальная — waveDim.
/// Клик/драг по дорожке вызывает [onSeek] (доля 0..1).
class WaveformView extends StatelessWidget {
  const WaveformView({
    super.key,
    required this.bars,
    this.progress = 0,
    this.buffered = 0,
    this.onSeek,
    this.height = 64,
    this.markers = const [],
  });

  final List<double> bars;
  final double progress;

  /// Доля буферизированного (0..1). Третий тиер между played и unplayed —
  /// видно «как далеко» зашёл preload (на плохом коннекте — где stall).
  final double buffered;
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
            onHorizontalDragUpdate: onSeek == null
                ? null
                : (d) => seekAt(d.localPosition),
            child: CustomPaint(
              size: Size(c.maxWidth, height),
              painter: _WaveformPainter(
                bars: bars,
                progress: progress,
                buffered: buffered,
                markers: markers,
              ),
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
    this.buffered = 0,
    this.markers = const [],
  });

  final List<double> bars;
  final double progress;
  final double buffered;
  final List<double> markers;

  static const double _gap = 1.5;
  static const double _minBar = 2;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;

    // Подгоняем число баров под ширину, чтобы не сжимать в кашу.
    final maxBars = (size.width / (_minBar + _gap)).floor().clamp(
      1,
      bars.length,
    );
    final step = bars.length / maxBars;
    final barWidth = (size.width - _gap * (maxBars - 1)) / maxBars;

    final mid = size.height / 2;
    final playedX = size.width * progress;
    // Граница буфера — никогда левее курсора (защита от bouncing буфера назад
    // при seek в неисчисленные секунды воспроизведения).
    final bufferedX = size.width * buffered.clamp(progress, 1.0);

    final played = Paint()..color = AppColors.acid;
    // Третий тиер: приглушённый acid между played и unplayed.
    final bufferedPaint = Paint()
      ..color = AppColors.acid.withValues(alpha: 0.35);
    final dim = Paint()..color = AppColors.waveDim;

    for (var i = 0; i < maxBars; i++) {
      final amp = bars[(i * step).floor()];
      final h = (amp * size.height).clamp(2.0, size.height);
      final x = i * (barWidth + _gap);
      final rect = Rect.fromLTWH(x, mid - h / 2, barWidth, h);
      final cx = x + barWidth / 2;
      final Paint p;
      if (cx <= playedX) {
        p = played;
      } else if (cx <= bufferedX) {
        p = bufferedPaint;
      } else {
        p = dim;
      }
      canvas.drawRect(rect, p);
    }

    // Маркеры комментариев — маленькие lime-точки над дорожкой.
    final marker = Paint()..color = AppColors.lime;
    for (final f in markers) {
      canvas.drawCircle(Offset(size.width * f, 3), 2.2, marker);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.progress != progress ||
      old.buffered != buffered ||
      old.bars != bars ||
      old.markers != markers;
}
