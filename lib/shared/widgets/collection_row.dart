import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/colors.dart';
import '../models/collection.dart';
import 'cover_art.dart';
import 'pressable.dart';

/// Компактный list-вариант [CollectionCard]: cover слева (квадрат/круг),
/// title + subtitle (mono), счётчик треков (mono справа), chevron. Те же
/// правила маршрутизации по `Collection.target` — карточка сама ведёт.
class CollectionRow extends StatelessWidget {
  const CollectionRow({super.key, required this.item});

  final Collection item;

  void _open(BuildContext context) {
    switch (item.target) {
      case CollectionTarget.track:
        context.go('/track/${item.id}');
      case CollectionTarget.playlist:
        context.go('/playlist/${item.id}');
      case CollectionTarget.artist:
        context.go('/artist/${Uri.encodeComponent(item.handle ?? item.title)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () => _open(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppTheme.borderRadius,
          border: AppTheme.border(),
        ),
        child: Row(
          children: [
            CoverArt(
              seed: item.coverSeed,
              imageUrl: item.coverUrl,
              size: 44,
              circular: item.isCircular,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textHi)),
                      ),
                      if (item.minted) ...[
                        const SizedBox(width: 6),
                        const Text('◆',
                            style: TextStyle(
                                color: AppColors.lime, fontSize: 11)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.mono(size: 11, color: AppColors.textMid)),
                ],
              ),
            ),
            if (item.trackCount > 0) ...[
              const SizedBox(width: 12),
              Text('${item.trackCount} tracks',
                  style: AppTheme.mono(size: 11, color: AppColors.textLow)),
            ],
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.textLow),
          ],
        ),
      ),
    );
  }
}
