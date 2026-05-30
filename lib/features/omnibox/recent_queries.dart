import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/prefs_store.dart';

/// Последние поисковые запросы (до 10), персистится в `prefs.json`.
/// Подаём в омнибокс когда поле пустое и есть фокус.
class RecentQueriesController extends Notifier<List<String>> {
  static const _store = PrefsStore();
  static const _key = 'recent_searches';
  static const _max = 10;

  @override
  List<String> build() {
    _restore();
    return const [];
  }

  Future<void> _restore() async {
    try {
      final raw = await _store.readString(_key);
      if (raw == null) return;
      final j = jsonDecode(raw);
      if (j is List) state = j.cast<String>();
    } catch (_) {
      /* в тестах плагина нет — тихо */
    }
  }

  void add(String q) {
    final qt = q.trim();
    if (qt.isEmpty) return;
    // Дедуп — если query уже был, поднимаем наверх.
    final next = <String>[
      qt,
      ...state.where((e) => e != qt),
    ].take(_max).toList();
    state = next;
    unawaited(_safe(() => _store.writeString(_key, jsonEncode(next))));
  }

  void clear() {
    state = const [];
    unawaited(_safe(() => _store.remove(_key)));
  }

  Future<void> _safe(Future<void> Function() op) async {
    try {
      await op();
    } catch (_) {}
  }
}

final recentQueriesProvider =
    NotifierProvider<RecentQueriesController, List<String>>(
      RecentQueriesController.new,
    );
