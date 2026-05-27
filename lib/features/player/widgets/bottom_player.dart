import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/colors.dart';
import '../../../shared/action_feedback.dart';
import '../../../shared/format.dart';
import '../../../shared/widgets/cover_art.dart';
import '../../../shared/widgets/pressable.dart';
import '../../../shared/widgets/waveform_view.dart';
import '../player_controller.dart';

class BottomPlayer extends ConsumerWidget {
  const BottomPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerControllerProvider);
    final c = ref.read(playerControllerProvider.notifier);
    final track = player.track;
    final enabled = track != null;

    return Container(
      height: AppTheme.playerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.72),
        border: const Border(top: AppTheme.borderSideStatic),
      ),
      child: Row(
        children: [
          // ── Контролы воспроизведения ───────────────────────────────────
          _IconBtn(
            icon: Icons.shuffle,
            active: player.shuffle,
            enabled: enabled,
            onTap: c.toggleShuffle,
          ),
          _IconBtn(
            icon: Icons.skip_previous,
            enabled: enabled,
            onTap: c.previous,
          ),
          _PlayButton(
            isPlaying: player.isPlaying,
            enabled: enabled,
            onTap: c.toggle,
          ),
          _IconBtn(icon: Icons.skip_next, enabled: enabled, onTap: c.next),
          _IconBtn(
            icon: Icons.repeat,
            active: player.repeat,
            enabled: enabled,
            onTap: c.toggleRepeat,
          ),
          const SizedBox(width: 18),

          if (track != null) ...[
            Pressable(
              onTap: () => context.go('/track/${track.id}'),
              child: CoverArt(seed: track.id, imageUrl: track.coverUrl, size: 44),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 150,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Pressable(
                    onTap: () => context.go('/track/${track.id}'),
                    child: Text(track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textHi)),
                  ),
                  const SizedBox(height: 2),
                  Pressable(
                    onTap: () => context
                        .go('/artist/${Uri.encodeComponent(track.artistHandle)}'),
                    child: Text(track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.mono(size: 11, color: AppColors.textMid)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Text(Fmt.time(player.position), style: AppTheme.mono(size: 11)),
            const SizedBox(width: 12),
            Expanded(
              child: WaveformView(
                bars: track.waveform,
                progress: player.progress,
                onSeek: c.seekFraction,
                height: 36,
              ),
            ),
            const SizedBox(width: 12),
            Text(Fmt.time(track.duration), style: AppTheme.mono(size: 11)),
            const SizedBox(width: 18),
            _IconBtn(
              icon: player.liked ? Icons.favorite : Icons.favorite_border,
              active: player.liked,
              enabled: true,
              onTap: () async {
                final outcome = await c.toggleLike();
                if (context.mounted) showLikeOutcome(context, outcome);
              },
            ),
            const SizedBox(width: 4),
            _Volume(volume: player.volume, onChanged: c.setVolume),
          ] else
            Expanded(
              child: Text('select a track',
                  style: AppTheme.mono(size: 12, color: AppColors.textLow)),
            ),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final bool enabled;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? AppColors.textLow
        : active
            ? AppColors.acid
            : AppColors.textMid;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}

class _Volume extends StatelessWidget {
  const _Volume({required this.volume, required this.onChanged});

  final double volume;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final icon = volume == 0
        ? Icons.volume_off
        : volume < 0.5
            ? Icons.volume_down
            : Icons.volume_up;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _IconBtn(
          icon: icon,
          enabled: true,
          onTap: () => onChanged(volume == 0 ? 1.0 : 0.0),
        ),
        SizedBox(
          width: 84,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              activeTrackColor: AppColors.textMid,
              inactiveTrackColor: AppColors.border,
              thumbColor: AppColors.textHi,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 11),
            ),
            child: Slider(value: volume, onChanged: onChanged),
          ),
        ),
      ],
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.isPlaying,
    required this.enabled,
    required this.onTap,
  });

  final bool isPlaying;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      enabled: enabled,
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: enabled ? AppColors.acid : AppColors.surface2,
          shape: BoxShape.circle,
        ),
        child: Icon(
          isPlaying ? Icons.pause : Icons.play_arrow,
          color: enabled ? AppColors.bg : AppColors.textLow,
          size: 24,
        ),
      ),
    );
  }
}
