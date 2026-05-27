import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/colors.dart';

/// web3-маркер «◆ minted» — lime на тёмном.
class MintedBadge extends StatelessWidget {
  const MintedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.lime.withValues(alpha: 0.08),
        borderRadius: AppTheme.borderRadius,
        border: Border.all(
          color: AppColors.lime.withValues(alpha: 0.4),
          width: AppTheme.borderWidth,
        ),
      ),
      child: Text(
        '◆ minted',
        style: AppTheme.mono(
          size: 10,
          color: AppColors.lime,
          weight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
