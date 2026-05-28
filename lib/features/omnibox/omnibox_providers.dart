import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Один shared FocusNode для омнибокса (поле в TopBar) — глобальный фокус
/// нужен для ⌘K и ⌘F shortcut'ов (фокус ставится из AppShell-Actions).
final omniboxFocusProvider = Provider<FocusNode>((ref) {
  final node = FocusNode(debugLabel: 'omnibox');
  ref.onDispose(node.dispose);
  return node;
});

/// Один shared TextEditingController, чтобы ⌘K / ⌘F мог сразу выделить
/// весь существующий текст (instant "пиши новое поверх").
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

/// true → дроп-даун показываем. Слушает FocusNode (он же ChangeNotifier).
class OmniboxFocusedController extends Notifier<bool> {
  FocusNode? _node;
  void _listener() {
    final n = _node;
    if (n != null && state != n.hasFocus) state = n.hasFocus;
  }

  @override
  bool build() {
    final n = ref.read(omniboxFocusProvider);
    _node = n;
    n.addListener(_listener);
    ref.onDispose(() => n.removeListener(_listener));
    return n.hasFocus;
  }
}

final omniboxFocusedProvider =
    NotifierProvider<OmniboxFocusedController, bool>(
        OmniboxFocusedController.new);
