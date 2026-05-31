/// Решает, должен ли горизонтальный свайп сработать как «назад».
/// Только от левого края, вправо, дальше порога, и если есть куда вернуться —
/// иначе он бы конкурировал с горизонтальными каруселями.
const double kBackEdgeStart = 48; // px от левого края
const double kBackThreshold = 64; // px горизонтального хода

bool shouldPopOnSwipe({
  required bool canPop,
  required double startDx,
  required double totalDx,
}) {
  if (!canPop) return false;
  if (startDx > kBackEdgeStart) return false;
  return totalDx >= kBackThreshold;
}
