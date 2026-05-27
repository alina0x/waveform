import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:talker_flutter/talker_flutter.dart';

import '../../core/log/talker.dart';

/// Встроенный экран логов (Talker): история запросов API, ошибок, событий
/// Riverpod. Открывается из TopBar (только в debug-сборке).
class LogsScreen extends ConsumerWidget {
  const LogsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TalkerScreen(talker: ref.watch(talkerProvider));
  }
}
