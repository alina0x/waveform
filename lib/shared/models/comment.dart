/// Комментарий, привязанный к позиции на waveform (как в каноне SoundCloud).
class Comment {
  const Comment({
    required this.author,
    required this.timecodeMs,
    required this.text,
  });

  final String author;
  final int timecodeMs;
  final String text;

  String get authorSeed => 'c-$author';

  /// Доля позиции на дорожке (0..1) для маркера на waveform.
  double fraction(int trackMs) =>
      trackMs == 0 ? 0 : (timecodeMs / trackMs).clamp(0.0, 1.0);
}
