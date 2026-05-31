import 'package:flutter_riverpod/flutter_riverpod.dart';

class ShortcutsOverlayOpen extends Notifier<bool> {
  @override
  bool build() => false;
  void open() => state = true;
  void close() => state = false;
}

final shortcutsOverlayOpenProvider =
    NotifierProvider<ShortcutsOverlayOpen, bool>(ShortcutsOverlayOpen.new);
