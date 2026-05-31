import 'package:waveform_app/core/api/liked_tracks.dart';

/// Заглушка лайков: build() возвращает фиксированный набор, без сети.
/// Переопределяет build() полностью, не вызывая super — чтобы не трогать
/// authControllerProvider и не делать HTTP-запросов.
class StubLikedTracks extends LikedTracksController {
  StubLikedTracks([this._ids = const <String>{}]);
  final Set<String> _ids;

  @override
  Set<String> build() => Set.unmodifiable(_ids);
}
