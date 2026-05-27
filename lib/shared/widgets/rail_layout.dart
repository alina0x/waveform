import 'package:flutter/material.dart';

import 'right_rail.dart';

/// Раскладка экрана с правым рейлом (Home, Feed): основной контент слева,
/// фиксированный рейл справа.
class RailLayout extends StatelessWidget {
  const RailLayout({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: child),
        const RightRail(),
      ],
    );
  }
}
