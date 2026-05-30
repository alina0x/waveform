import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/colors.dart';
import '../../shared/models/track.dart';
import '../../shared/widgets/cover_art.dart';
import '../../shared/widgets/pressable.dart';
import '../player/player_controller.dart';
import 'queue_visibility.dart';

/// Правая queue-панель. Сверху — playing-карточка, под ней — реорордерится
/// список "up next". Закрыть — крестик в шапке или toggle в TopBar.
class QueuePanel extends ConsumerWidget {
  const QueuePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerControllerProvider);
    // Подписка на queueVersion → когда меняется queue, перечитываем upcoming.
    ref.watch(playerControllerProvider.select((s) => s.queueVersion));
    final pc = ref.read(playerControllerProvider.notifier);
    final upcoming = pc.upcomingTracks;
    final current = player.track;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: AppTheme.borderSideStatic),
      ),
      child: Column(
        children: [
          _Header(
            current: current,
            upcomingCount: upcoming.length,
            onClose: () => ref.read(queueVisibleProvider.notifier).hide(),
          ),
          const Divider(color: AppColors.border, height: 0.5, thickness: 0.5),
          Expanded(
            child: upcoming.isEmpty
                ? const _EmptyUpcoming()
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                    itemCount: upcoming.length,
                    buildDefaultDragHandles: false,
                    onReorder: pc.reorderUpcoming,
                    proxyDecorator: (child, _, _) =>
                        Material(color: Colors.transparent, child: child),
                    itemBuilder: (context, index) {
                      final t = upcoming[index];
                      return _QueueRow(
                        key: ValueKey('q-${t.id}'),
                        track: t,
                        index: index,
                        onRemove: () => pc.removeFromQueue(t.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.current,
    required this.upcomingCount,
    required this.onClose,
  });
  final Track? current;
  final int upcomingCount;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'QUEUE',
                  style: AppTheme.mono(
                    size: 10,
                    color: AppColors.textLow,
                    weight: FontWeight.w600,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              Pressable(
                onTap: onClose,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 14, color: AppColors.textMid),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (current != null)
            Row(
              children: [
                CoverArt(
                  seed: current!.id,
                  imageUrl: current!.coverUrl,
                  size: 40,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        current!.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textHi,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        current!.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.mono(
                          size: 11,
                          color: AppColors.textMid,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else
            Text(
              'nothing playing',
              style: AppTheme.mono(size: 12, color: AppColors.textMid),
            ),
          const SizedBox(height: 12),
          Text(
            upcomingCount == 0 ? 'UP NEXT' : 'UP NEXT · $upcomingCount',
            style: AppTheme.mono(
              size: 10,
              color: AppColors.textLow,
              weight: FontWeight.w600,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyUpcoming extends StatelessWidget {
  const _EmptyUpcoming();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Text(
          'queue is empty\nplay a playlist to see what\'s next',
          textAlign: TextAlign.center,
          style: AppTheme.mono(size: 11, color: AppColors.textLow),
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    super.key,
    required this.track,
    required this.index,
    required this.onRemove,
  });
  final Track track;
  final int index;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: AppTheme.borderRadius,
        border: AppTheme.border(),
      ),
      child: Row(
        children: [
          Pressable(
            onTap: () => context.go('/track/${track.id}'),
            child: CoverArt(seed: track.id, imageUrl: track.coverUrl, size: 36),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textHi,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.mono(size: 10, color: AppColors.textMid),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Pressable(
            onTap: onRemove,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 13, color: AppColors.textLow),
            ),
          ),
          // Drag-handle для ReorderableListView. Помещаем в самый правый край.
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.only(left: 2, right: 4),
              child: Icon(
                Icons.drag_handle,
                size: 16,
                color: AppColors.textLow,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
