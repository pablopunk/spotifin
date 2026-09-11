import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../app/theme.dart';
import '../../platform/airplay_control.dart';
import '../../services/playback/playback_service.dart';
import '../../storage/database.dart';
import '../common/artwork.dart';
import '../common/design_system.dart';
import 'volume_scale.dart';

class DesktopPlayerBar extends StatelessWidget {
  const DesktopPlayerBar({
    required this.track,
    required this.playback,
    required this.onOpenPlayer,
    required this.onOpenQueue,
    required this.onOpenLyrics,
    required this.glass,
    super.key,
  });

  final Track track;
  final PlaybackService playback;
  final VoidCallback onOpenPlayer;
  final VoidCallback onOpenQueue;
  final VoidCallback onOpenLyrics;
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final content = SafeArea(
      top: false,
      child: SizedBox(
        height: 88,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SpotifinSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _TrackSummary(track: track, onTap: onOpenPlayer),
                ),
              ),
              Expanded(flex: 2, child: _DesktopTransport(playback: playback)),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _DesktopUtilities(
                    playback: playback,
                    onOpenQueue: onOpenQueue,
                    onOpenLyrics: onOpenLyrics,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!glass) {
      return Material(
        color: Colors.black,
        elevation: 20,
        shadowColor: Colors.black,
        child: content,
      );
    }
    return GlassContainer(
      useOwnLayer: true,
      quality: GlassQuality.premium,
      shape: const LiquidRoundedSuperellipse(borderRadius: 16),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }
}

class MobilePlayerBar extends StatelessWidget {
  const MobilePlayerBar({
    required this.track,
    required this.playback,
    required this.onOpenPlayer,
    required this.glass,
    super.key,
  });

  final Track track;
  final PlaybackService playback;
  final VoidCallback onOpenPlayer;
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final content = Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onOpenPlayer,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MobileProgress(playback: playback),
              ListTile(
                minTileHeight: 72,
                leading: Artwork(
                  itemId: track.albumId ?? track.id,
                  size: 48,
                  borderRadius: SpotifinRadii.small,
                ),
                title: Text(
                  track.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                subtitle: Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Previous',
                      onPressed: playback.previous,
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                    SpotifinPlayButton(
                      onPressed: playback.toggle,
                      playing: playback.playing,
                    ),
                    IconButton(
                      tooltip: 'Next',
                      onPressed: playback.next,
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!glass) {
      return Material(
        color: SpotifinColors.surface,
        elevation: 16,
        shadowColor: Colors.black,
        child: content,
      );
    }
    return GlassContainer(
      useOwnLayer: true,
      quality: GlassQuality.premium,
      shape: const LiquidRoundedSuperellipse(borderRadius: 16),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }
}

class _TrackSummary extends StatelessWidget {
  const _TrackSummary({required this.track, required this.onTap});

  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(SpotifinRadii.small),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Artwork(
            itemId: track.albumId ?? track.id,
            size: 56,
            borderRadius: SpotifinRadii.small,
          ),
          const SizedBox(width: SpotifinSpacing.sm),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _DesktopTransport extends StatelessWidget {
  const _DesktopTransport({required this.playback});

  final PlaybackService playback;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      SizedBox(
        height: 40,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ToggleButton(
              tooltip: 'Shuffle',
              active: playback.shuffle,
              onPressed: playback.toggleShuffle,
              icon: Icons.shuffle_rounded,
            ),
            IconButton(
              tooltip: 'Previous',
              onPressed: playback.previous,
              icon: const Icon(Icons.skip_previous_rounded),
            ),
            _PlayButton(playback: playback),
            IconButton(
              tooltip: 'Next',
              onPressed: playback.next,
              icon: const Icon(Icons.skip_next_rounded),
            ),
            _ToggleButton(
              tooltip: 'Repeat',
              active: playback.loopMode != LoopMode.off,
              onPressed: playback.cycleRepeat,
              icon: playback.loopMode == LoopMode.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
            ),
          ],
        ),
      ),
      _ProgressSlider(playback: playback),
    ],
  );
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playback});

  final PlaybackService playback;

  @override
  Widget build(BuildContext context) => IconButton.filled(
    tooltip: playback.playing ? 'Pause' : 'Play',
    style: IconButton.styleFrom(
      backgroundColor: SpotifinColors.text,
      foregroundColor: Colors.black,
      minimumSize: const Size.square(32),
      maximumSize: const Size.square(32),
      padding: EdgeInsets.zero,
    ),
    onPressed: playback.toggle,
    icon: Icon(
      playback.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
      size: 22,
    ),
  );
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.tooltip,
    required this.active,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final bool active;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    color: active ? SpotifinColors.accent : SpotifinColors.textMuted,
    onPressed: onPressed,
    icon: Icon(icon, size: 20),
  );
}

class _ProgressSlider extends StatelessWidget {
  const _ProgressSlider({required this.playback});

  final PlaybackService playback;

  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(
    stream: playback.player.positionStream,
    builder: (context, snapshot) {
      final position = snapshot.data ?? Duration.zero;
      final duration = playback.player.duration ?? Duration.zero;
      final maximum = duration.inMilliseconds.toDouble().clamp(
        1.0,
        double.infinity,
      );
      return Row(
        children: [
          _TimeLabel(position),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: position.inMilliseconds.toDouble().clamp(0.0, maximum),
                max: maximum,
                onChanged: (value) =>
                    playback.seek(Duration(milliseconds: value.round())),
              ),
            ),
          ),
          _TimeLabel(duration),
        ],
      );
    },
  );
}

class _TimeLabel extends StatelessWidget {
  const _TimeLabel(this.duration);

  final Duration duration;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 42,
    child: Text(
      _formatTime(duration),
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.labelSmall
          ?.copyWith(color: SpotifinColors.textMuted),
    ),
  );
}

class _DesktopUtilities extends StatelessWidget {
  const _DesktopUtilities({
    required this.playback,
    required this.onOpenQueue,
    required this.onOpenLyrics,
  });

  final PlaybackService playback;
  final VoidCallback onOpenQueue;
  final VoidCallback onOpenLyrics;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: 'Lyrics',
        onPressed: onOpenLyrics,
        icon: const Icon(Icons.lyrics_outlined, size: 19),
      ),
      IconButton(
        tooltip: 'Queue',
        onPressed: onOpenQueue,
        icon: const Icon(Icons.queue_music_rounded, size: 20),
      ),
      const SizedBox(width: SpotifinSpacing.sm),
      if (AirPlayControl.isSupported) const AirPlayControl(),
      const Icon(Icons.volume_up_rounded, size: 20),
      SizedBox(
        width: 144,
        child: StreamBuilder<double>(
          stream: playback.volumeStream,
          initialData: playback.volume,
          builder: (context, snapshot) => Slider(
            value: sliderFromVolume(snapshot.data ?? 1),
            onChanged: (position) =>
                playback.setVolume(volumeFromSlider(position)),
          ),
        ),
      ),
    ],
  );
}

class _MobileProgress extends StatelessWidget {
  const _MobileProgress({required this.playback});

  final PlaybackService playback;

  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(
    stream: playback.player.positionStream,
    builder: (context, snapshot) {
      final maximum = playback.player.duration?.inMilliseconds.toDouble() ?? 1;
      return LinearProgressIndicator(
        value: (snapshot.data?.inMilliseconds ?? 0).clamp(0, maximum) / maximum,
        minHeight: 2,
      );
    },
  );
}

String _formatTime(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
