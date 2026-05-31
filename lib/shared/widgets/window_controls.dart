import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/colors.dart';

/// Windows/Linux title-bar replacement: minimize / maximize-restore / close.
///
/// Mounted from [TopBar] only on Windows + Linux (macOS keeps its native
/// traffic lights via `titleBarStyle: hidden`). The bar around it uses
/// `DragToMoveArea` for dragging; these interactive children win the
/// hit-test on tap so the window only drags from empty zones.
///
/// State is purely visual (maximize glyph swap on maximize/restore) and
/// piped from `WindowListener` callbacks — no providers, no persistence.
class WindowControls extends StatefulWidget {
  const WindowControls({super.key});

  @override
  State<WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<WindowControls> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // The window may already be maximized (restored from previous session).
    // Plugin call is async, so the initial paint shows the maximize glyph
    // and we patch it once the call resolves.
    _syncMaximized();
  }

  Future<void> _syncMaximized() async {
    try {
      final m = await windowManager.isMaximized();
      if (mounted && m != _maximized) setState(() => _maximized = m);
    } catch (_) {
      // Plugin not wired (e.g. tests, unsupported platform) — leave default.
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _maximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _maximized = false);
  }

  Future<void> _toggleMaximize() async {
    // Read live state — listener events occasionally drop on Linux/X11.
    final isMax = await windowManager.isMaximized();
    if (isMax) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ControlButton(
          tooltip: 'minimize',
          icon: Icons.minimize,
          // Material's `Icons.minimize` sits at baseline; nudge it up so the
          // dash visually centers in the 32px button (Windows convention).
          iconOffset: const Offset(0, -4),
          onTap: () => windowManager.minimize(),
        ),
        _ControlButton(
          tooltip: _maximized ? 'restore' : 'maximize',
          // `filter_none` = two overlapping squares, the Windows "restore"
          // glyph; `crop_square` is the single-square maximize glyph.
          icon: _maximized ? Icons.filter_none : Icons.crop_square,
          iconSize: _maximized ? 12 : 14,
          onTap: _toggleMaximize,
        ),
        _ControlButton(
          tooltip: 'close',
          icon: Icons.close,
          hoverColor: const Color(0xFFE81123), // Windows close-button red.
          hoverIconColor: Colors.white,
          onTap: () => windowManager.close(),
        ),
      ],
    );
  }
}

class _ControlButton extends StatefulWidget {
  const _ControlButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.iconSize = 14,
    this.iconOffset = Offset.zero,
    this.hoverColor = AppColors.surface2,
    this.hoverIconColor,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final double iconSize;
  final Offset iconOffset;
  final Color hoverColor;

  /// Optional icon-tint override for the hover state (close button uses
  /// white on red; min/max keep the default textMid colour).
  final Color? hoverIconColor;

  @override
  State<_ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<_ControlButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final iconColor = _hover
        ? (widget.hoverIconColor ?? AppColors.textHi)
        : AppColors.textMid;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Tooltip(
          message: widget.tooltip,
          child: AnimatedContainer(
            duration: AppTheme.motion,
            width: 46,
            height: 32,
            color: _hover ? widget.hoverColor : Colors.transparent,
            alignment: Alignment.center,
            child: Transform.translate(
              offset: widget.iconOffset,
              child: Icon(widget.icon, size: widget.iconSize, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}
