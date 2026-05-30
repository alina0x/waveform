import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/colors.dart';
import 'section_header.dart';

/// Горизонтальная карусель секции: заголовок + стрелки прокрутки (десктоп)
/// + плавное затухание правого края как намёк на продолжение.
class MediaCarousel extends StatefulWidget {
  const MediaCarousel({
    super.key,
    required this.title,
    required this.height,
    required this.children,
    this.seeAll = true,
  });

  final String title;
  final double height;
  final List<Widget> children;
  final bool seeAll;

  @override
  State<MediaCarousel> createState() => _MediaCarouselState();
}

class _MediaCarouselState extends State<MediaCarousel> {
  final _ctrl = ScrollController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _nudge(int dir) {
    if (!_ctrl.hasClients) return;
    final target = (_ctrl.offset + dir * 480).clamp(
      0.0,
      _ctrl.position.maxScrollExtent,
    );
    _ctrl.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: widget.title,
          trailing: Row(
            children: [
              if (widget.seeAll) ...[
                Text(
                  'see all',
                  style: AppTheme.mono(size: 11, color: AppColors.textLow),
                ),
                const SizedBox(width: 14),
              ],
              _Arrow(icon: Icons.chevron_left, onTap: () => _nudge(-1)),
              const SizedBox(width: 6),
              _Arrow(icon: Icons.chevron_right, onTap: () => _nudge(1)),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.headerGap),
        SizedBox(
          height: widget.height,
          child: ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Colors.white, Colors.white, Colors.transparent],
              stops: [0, 0.95, 1],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: ListView.separated(
              controller: _ctrl,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 24),
              itemCount: widget.children.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: AppTheme.cardGap),
              itemBuilder: (_, i) => widget.children[i],
            ),
          ),
        ),
      ],
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: AppTheme.borderRadius,
            border: AppTheme.border(),
          ),
          child: Icon(icon, size: 16, color: AppColors.textMid),
        ),
      ),
    );
  }
}
