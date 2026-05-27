import 'package:flutter/material.dart';

import 'router.dart';
import 'theme/app_theme.dart';

class WaveformApp extends StatelessWidget {
  const WaveformApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Waveform',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: appRouter,
    );
  }
}
