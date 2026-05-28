import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// FocusNode для TextField внутри **центральной модалки**. Когда модалка
/// смонтирована, поле автофокусится; вне модалки этот node detached.
final omniboxFocusProvider = Provider<FocusNode>((ref) {
  final node = FocusNode(debugLabel: 'omnibox');
  ref.onDispose(node.dispose);
  return node;
});

/// Один shared TextEditingController — переживает закрытие/открытие модалки,
/// так что Esc + повторное ⌘K возвращают тот же запрос (как Raycast/Spotlight).
final omniboxControllerProvider = Provider<TextEditingController>((ref) {
  final ctrl = TextEditingController();
  ref.onDispose(ctrl.dispose);
  return ctrl;
});

/// Текущий debounced query в омнибоксе (обновляется через 250ms после ввода);
/// используется и для дроп-дауна, и для navigation на /search через Enter.
class OmniboxQueryController extends Notifier<String> {
  @override
  String build() => '';
  void set(String v) {
    if (state != v) state = v;
  }
}

final omniboxQueryProvider =
    NotifierProvider<OmniboxQueryController, String>(OmniboxQueryController.new);

/// Открыта ли центральная палитра. Источник правды для AppShell — рендерит
/// blur-фон + модалку только когда true. Toggle/open/close из shortcut'ов,
/// trigger-кнопки в TopBar и Esc внутри модалки.
class OmniboxOpenController extends Notifier<bool> {
  @override
  bool build() => false;
  void open() => state = true;
  void close() => state = false;
  void toggle() => state = !state;
}

final omniboxOpenProvider =
    NotifierProvider<OmniboxOpenController, bool>(OmniboxOpenController.new);
