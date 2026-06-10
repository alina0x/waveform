import 'package:waveform_app/core/api/js_runner.dart';

/// Скриптуемый фейк: на каждую инъекцию fetch() выдаёт следующий HTTP-статус
/// из очереди [statuses]; poll-чтение возвращает застейдженный статус как JSON.
class FakeJsRunner implements JsRunner {
  FakeJsRunner(this.statuses);

  /// Очередь статусов, отдаваемых по порядку на каждый fetch-инъект.
  final List<int> statuses;
  int _i = 0;
  int? _pending;

  /// Записанные инъектированные fetch-скрипты (для проверки method/path).
  final List<String> injected = [];
  int launchCount = 0;
  int closeCount = 0;

  int _next() => _i < statuses.length ? statuses[_i++] : 0;

  @override
  Future<void> launch(String url) async => launchCount++;

  @override
  Future<void> close() async => closeCount++;

  @override
  Future<String?> eval(String javaScript) async {
    if (javaScript.contains('fetch(')) {
      injected.add(javaScript);
      _pending = _next();
      return null;
    }
    // poll-чтение глобалки результата
    // Упрощение: результат отдаётся ровно один раз на инъекцию (реальный webview
    // держит window.__wfRes до следующего сброса). Executor читает до первого
    // non-null, так что для тестов этого достаточно.
    final p = _pending;
    _pending = null;
    return p == null ? null : '{"status":$p}';
  }
}
