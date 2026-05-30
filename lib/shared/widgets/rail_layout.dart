import 'package:flutter/material.dart';

import 'right_rail.dart';

/// Раскладка экрана с правым рейлом (Home, Feed): основной контент слева,
/// фиксированный рейл справа.
class RailLayout extends StatelessWidget {
  const RailLayout({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Рейл приклеен к правому краю окна (последний в full-width Row). Контент
    // центрируется в оставшейся слева области и ограничен макс-шириной ~960
    // (как контент-колонка трек-страницы) — на широких экранах не растягивается.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: child,
            ),
          ),
        ),
        const RightRail(),
      ],
    );
  }
}
