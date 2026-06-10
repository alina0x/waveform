import 'package:flutter_test/flutter_test.dart';
import 'package:talker_flutter/talker_flutter.dart';
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
      warmSettle: Duration.zero,
      warmRetryDelay: Duration.zero,
    );

void main() {
  test('warm-up probes /me, then a PUT returns its status', () async {
    final runner = FakeJsRunner([200, 201]);
    final ex = build(runner);

    final status = await ex.send(method: 'PUT', path: '/users/1/track_likes/9');

    expect(status, 201);
    expect(runner.launchCount, 1);
    expect(runner.injected[0], contains('"GET"'));
    expect(runner.injected[0], contains('/me'));
    expect(runner.injected[1], contains('"PUT"'));
    expect(runner.injected[1], contains('/users/1/track_likes/9'));
    expect(runner.injected[1], contains('OAuth tok'));
    expect(runner.injected[1], contains('client_id=cid'));
  });

  test('on 403 it re-warms and retries once, returning the retry status', () async {
    final runner = FakeJsRunner([200, 403, 200, 200]);
    final ex = build(runner);

    final status = await ex.send(method: 'PUT', path: '/users/1/track_likes/9');

    expect(status, 200);
    expect(runner.launchCount, 2);
  });

  test('a still-403 after re-warm surfaces 403 (caller maps to blocked)', () async {
    final runner = FakeJsRunner([200, 403, 200, 403]);
    final ex = build(runner);

    final status = await ex.send(method: 'PUT', path: '/users/1/track_likes/9');

    expect(status, 403);
    expect(runner.launchCount, 2);
  });

  test('concurrent sends run serialized in call order (warm-up once)', () async {
    final runner = FakeJsRunner([200, 201, 202]);
    final ex = build(runner);

    final f1 = ex.send(method: 'PUT', path: '/users/1/track_likes/1');
    final f2 = ex.send(method: 'PUT', path: '/users/1/track_likes/2');
    final results = await Future.wait([f1, f2]);

    expect(results, [201, 202]);
    expect(runner.launchCount, 1);
    expect(runner.injected[1], contains('/track_likes/1'));
    expect(runner.injected[2], contains('/track_likes/2'));
  });

  test('throws when there is no token (caller falls back to Dio)', () async {
    final runner = FakeJsRunner([200]);
    final ex = WebviewApiExecutor(
      createRunner: () async => runner,
      tokenGetter: () async => null,
      clientIdGetter: () async => 'cid',
      log: TalkerFlutter.init(),
      pollInterval: Duration.zero,
      maxPolls: 4,
      warmAttempts: 3,
      warmSettle: Duration.zero,
      warmRetryDelay: Duration.zero,
    );

    await expectLater(
      ex.send(method: 'PUT', path: '/users/1/track_likes/9'),
      throwsA(isA<StateError>()),
    );
  });

  test('warm-up exhaustion throws StateError', () async {
    final runner = FakeJsRunner([403, 403, 403]);
    final ex = build(runner); // warmAttempts: 3

    await expectLater(
      ex.send(method: 'PUT', path: '/users/1/track_likes/9'),
      throwsA(isA<StateError>()),
    );
  });
}
