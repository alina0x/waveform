import 'package:flutter/material.dart';

/// Apple-like тактильность: лёгкое spring-сжатие при нажатии + pointer-курсор.
/// Оборачивает любой интерактивный элемент.
///
/// Hover-подсветка специально НЕ рисуется — для разнородных детей (круг,
/// прямоугольник, ряд) она выглядела как квадратное halo вне формы. Если
/// нужен hover-эффект, реализуй его на самом ребёнке (border/opacity/scale).
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
    this.enabled = true,
    @Deprecated('No-op; hover fill was removed') this.hoverFill = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool enabled;
  final bool hoverFill;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _setDown(bool v) {
    if (widget.enabled && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && widget.onTap != null;
    return MouseRegion(
      cursor: active ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        onTapDown: (_) => _setDown(true),
        onTapUp: (_) => _setDown(false),
        onTapCancel: () => _setDown(false),
        child: AnimatedScale(
          scale: _down ? widget.scale : 1,
          duration: Duration(milliseconds: _down ? 90 : 220),
          // Лёгкий «отскок» на отпускании — пружинный характер.
          curve: _down ? Curves.easeOut : Curves.easeOutBack,
          child: widget.child,
        ),
      ),
    );
  }
}
