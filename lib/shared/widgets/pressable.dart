import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/colors.dart';

/// Apple-like тактильность: лёгкое spring-сжатие при нажатии + pointer-курсор +
/// мягкая hover-подсветка (как в Finder). Оборачивает любой интерактивный элемент.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
    this.enabled = true,
    this.hoverFill = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool enabled;

  /// Включает едва заметную fill-подсветку на hover. Выключайте на круглых
  /// детях (avatar'ы) — иначе вокруг кружка появляется квадратный halo.
  final bool hoverFill;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  bool _hover = false;

  void _setDown(bool v) {
    if (widget.enabled && _down != v) setState(() => _down = v);
  }

  void _setHover(bool v) {
    if (widget.enabled && _hover != v) setState(() => _hover = v);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && widget.onTap != null;
    final showHover = widget.hoverFill && _hover && active && !_down;
    // Тонкая (alpha 0.04) подложка из `textHi` — еле видна, не дерёт глаз, но
    // на однотонной поверхности явно «оживляет» элемент при наведении.
    return MouseRegion(
      cursor: active ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: active ? (_) => _setHover(true) : null,
      onExit: active ? (_) => _setHover(false) : null,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        onTapDown: (_) => _setDown(true),
        onTapUp: (_) => _setDown(false),
        onTapCancel: () => _setDown(false),
        child: Container(
          // `decoration: null` когда нет hover — без декорации Container не
          // навязывает прямоугольной формы детям (важно для круглых аватарок).
          decoration: showHover
              ? BoxDecoration(
                  color: AppColors.textHi.withValues(alpha: 0.04),
                  borderRadius: AppTheme.borderRadius,
                )
              : null,
          child: AnimatedScale(
            scale: _down ? widget.scale : 1,
            duration: Duration(milliseconds: _down ? 90 : 220),
            // Лёгкий «отскок» на отпускании — пружинный характер.
            curve: _down ? Curves.easeOut : Curves.easeOutBack,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
