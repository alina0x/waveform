import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/datadome_store.dart';
import '../core/api/soundcloud_api.dart';
import '../core/api/webview_login.dart';
import 'widgets/toast.dart';

/// Реакция UI на исход API-write (лайк/репост). Тихо при [LikeOutcome.ok]; при
/// `blocked` — предложение пройти верификацию в браузере (капча/анти-абуз,
/// частый под VPN); при `failed` — короткое уведомление с указанием действия.
void showWriteOutcome(
  BuildContext context,
  LikeOutcome outcome, {
  String verb = 'like',
}) {
  if (outcome == LikeOutcome.ok) return;
  final blocked = outcome == LikeOutcome.blocked;
  showToast(
    context,
    blocked
        ? 'SoundCloud blocked this action — likely a captcha/VPN check'
        : "couldn't update $verb",
    duration: Duration(seconds: blocked ? 6 : 3),
    action: blocked ? (label: 'verify', onTap: () => _verify(context)) : null,
  );
}

/// Opens the verification WebView and pipes any captured SC bypass
/// cookies (`datadome`, `sc_tracking_anonymous_id`, …) into the
/// [DataDomeStore]. The next mutating request carries them; if the user
/// solved DataDome's captcha while the WebView was open, the cookie is
/// now blessed and `track_likes` PUT returns 200 instead of 403.
Future<void> _verify(BuildContext context) async {
  // Capture the container before any awaits — context may become unmounted
  // while the user is interacting with the WebView.
  final container = ProviderScope.containerOf(context, listen: false);
  final cookies = await WebviewLogin.openVerification();
  if (cookies.isEmpty) return;
  await container.read(dataDomeProvider.notifier).adopt(cookies);
}

/// Старая точка входа — оставлена для уже-существующих call-сайтов (TrackRow,
/// bottom_player); делегирует в обобщённый [showWriteOutcome].
void showLikeOutcome(BuildContext context, LikeOutcome outcome) =>
    showWriteOutcome(context, outcome, verb: 'like');

/// Уведомление, что трек доступен только по подписке GO+ и не проигрывается.
void showGoPlusNotice(BuildContext context) {
  showToast(
    context,
    'GO+ only — needs a SoundCloud GO+ subscription to play',
    duration: const Duration(seconds: 3),
  );
}
