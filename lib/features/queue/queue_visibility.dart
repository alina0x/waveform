import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Видимость правой queue-панели. По умолчанию скрыта.
/// Иконка в TopBar (queue_music) — toggle.
class QueueVisibilityController extends Notifier<bool> {
  @override
  bool build() => false;
  void toggle() => state = !state;
  void show() => state = true;
  void hide() => state = false;
}

final queueVisibleProvider = NotifierProvider<QueueVisibilityController, bool>(
  QueueVisibilityController.new,
);
