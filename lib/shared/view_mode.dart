import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/prefs_store.dart';

/// Режим отображения коллекций — плитки vs компактный список.
/// Применяется в library / search / playlist-сетках; глобальная пользовательская
/// настройка (персистится в `prefs.json`).
enum ViewMode { tiles, list }

class ViewModeController extends Notifier<ViewMode> {
  static const _store = PrefsStore();
  static const _key = 'viewMode';

  @override
  ViewMode build() {
    _restore();
    return ViewMode.tiles; // дефолт — Apple-like компактные плитки
  }

  Future<void> _restore() async {
    try {
      final v = await _store.readString(_key);
      if (v == ViewMode.list.name) state = ViewMode.list;
    } catch (_) {/* плагина нет в тестах — игнорируем */}
  }

  void set(ViewMode mode) {
    if (state == mode) return;
    state = mode;
    unawaited(_safe(() => _store.writeString(_key, mode.name)));
  }

  void toggle() =>
      set(state == ViewMode.tiles ? ViewMode.list : ViewMode.tiles);

  Future<void> _safe(Future<void> Function() op) async {
    try {
      await op();
    } catch (_) {}
  }
}

final viewModeProvider =
    NotifierProvider<ViewModeController, ViewMode>(ViewModeController.new);
