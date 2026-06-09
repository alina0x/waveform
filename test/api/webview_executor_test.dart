import 'package:flutter_test/flutter_test.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:waveform_app/core/api/js_runner.dart';
import 'package:waveform_app/core/api/webview_executor.dart';

import '../support/fake_js_runner.dart';

WebviewApiExecutor build(FakeJsRunner runner) => WebviewApiExecutor(
      createRunner: () async => runner,
      tokenGetter: () async => 'tok',
      clientIdGetter: () async => 'cid',
      log: TalkerFlutter.init(),
      pollInterval: Duration.zero,
      maxPolls: 4,
      warmAttempts: 3,
    );

void main() {
  test('warm-up probes /me, then a PUT returns its status', () async {
    // statuses: [warm probe GET /me, the PUT]
    final runner = FakeJsRunner([200, 201]);
    final ex = build(runner);

    final status = await ex.send(method: 'PUT', path: '/users/1/track_likes/9');

    expect(status, 201);
    expect(runner.launchCount, 1); // warmed once
    // First inject is the warm probe (GET /me), second is the PUT.
    expect(runner.injected[0], contains('"GET"'));
    expect(runner.injected[0], contains('/me'));
    expect(runner.injected[1], contains('"PUT"'));
    expect(runner.injected[1], contains('/users/1/track_likes/9'));
    expect(runner.injected[1], contains('OAuth tok'));
    expect(runner.injected[1], contains('client_id=cid'));
  });
}
