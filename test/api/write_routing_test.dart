import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talker_flutter/talker_flutter.dart';
import 'package:waveform_app/core/api/client_id_resolver.dart';
import 'package:waveform_app/core/api/http_soundcloud_api.dart';
import 'package:waveform_app/core/api/soundcloud_api.dart';
import 'package:waveform_app/core/api/soundcloud_auth.dart';
import 'package:waveform_app/core/api/webview_executor.dart';

import '../support/fake_js_runner.dart';

HttpSoundcloudApi apiWith(WebviewApiExecutor? ex) => HttpSoundcloudApi(
      Dio(),
      ClientIdResolver(Dio()),
      auth: const SoundcloudAuth(clientId: 'cid', userToken: 'tok'),
      executor: ex,
      talker: TalkerFlutter.init(),
    );

WebviewApiExecutor exWith(List<int> statuses) => WebviewApiExecutor(
      createRunner: () async => FakeJsRunner(statuses),
      tokenGetter: () async => 'tok',
      clientIdGetter: () async => 'cid',
      log: TalkerFlutter.init(),
      pollInterval: Duration.zero,
      maxPolls: 4,
      warmAttempts: 3,
    );

void main() {
  test('writeOutcome maps executor 200/201 → ok', () async {
    final api = apiWith(exWith([200, 201])); // warm 200, write 201
    final out = await api.writeOutcome('PUT', '/users/1/track_likes/9');
    expect(out, LikeOutcome.ok);
  });

  test('writeOutcome maps executor 403 (post-retry) → blocked', () async {
    final api = apiWith(exWith([200, 403, 200, 403]));
    final out = await api.writeOutcome('PUT', '/users/1/track_likes/9');
    expect(out, LikeOutcome.blocked);
  });
}
