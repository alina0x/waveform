import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/colors.dart';
import '../view_mode.dart';
import 'pressable.dart';

/// Apple-like мини-переключатель «вид»: две квадратные иконки tiles | list,
/// активная — `textHi`, неактивная — `textLow`, общий тонкий border.
class ViewToggle extends ConsumerWidget {
  const ViewToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(viewModeProvider);
    final c = ref.read(viewModeProvider.notifier);
    return Container(
      decoration: BoxDecoration(
        borderRadius: AppTheme.borderRadius,
        border: AppTheme.border(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Btn(
            icon: Icons.grid_view_rounded,
            active: mode == ViewMode.tiles,
            onTap: () => c.set(ViewMode.tiles),
            tooltip: 'tiles',
          ),
          Container(width: 0.5, height: 22, color: AppColors.border),
          _Btn(
            icon: Icons.format_list_bulleted_rounded,
            active: mode == ViewMode.list,
            onTap: () => c.set(ViewMode.list),
            tooltip: 'list',
          ),
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({
    required this.icon,
    required this.active,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Pressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          color: active ? AppColors.surface2 : Colors.transparent,
          child: Icon(
            icon,
            size: 15,
            color: active ? AppColors.textHi : AppColors.textLow,
          ),
        ),
      ),
    );
  }
}
