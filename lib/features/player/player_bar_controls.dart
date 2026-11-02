import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../app/theme.dart';
import '../../platform/airplay_control.dart';
import '../../services/playback/active_playback.dart';
import '../../storage/database.dart';
import '../common/artwork.dart';
import '../common/design_system.dart';
import '../common/glass.dart';
import 'cast_button.dart';
import 'playback_position_slider.dart';
import 'player_collection_links.dart';
import 'player_panel_tabs.dart';
import 'remote_devices.dart';

class DesktopPlayerBar extends StatelessWidget {
  const DesktopPlayerBar({
    required this.track,
    required this.active,
    required this.onOpenPlayer,
    required this.onOpenQueue,
    required this.onOpenLyrics,
    required this.glass,
    required this.glassOpacity,
    this.usesSidePanel = false,
    super.key,
  });

  final Track track;
  final ActivePlayback active;
  final VoidCallback onOpenPlayer;
  final VoidCallback onOpenQueue;
  final VoidCallback onOpenLyrics;
  final bool glass;
  final double glassOpacity;
  final bool usesSidePanel;

  @override
  Widget build(BuildContext context) {
    final content = SafeArea(
      top: false,
      child: SizedBox(
        height: 88,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SpotifinSpacing.md),
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _TrackSummary(track: track, onTap: onOpenPlayer),
                  ),
                ),
                Expanded(
                  flex: constraints.maxWidth >= SpotifinBreakpoints.extendedRail
                      ? 2
                      : 1,
                  child: DesktopTransport(active: active),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _DesktopUtilities(
                      active: active,
                      usesSidePanel: usesSidePanel,
                      onOpenQueue: onOpenQueue,
                      onOpenLyrics: onOpenLyrics,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return PlayerBarSurface(
      glass: glass,
      glassOpacity: glassOpacity,
      child: content,
    );
  }
}

class PlayerBarSurface extends StatelessWidget {
  const PlayerBarSurface({
    required this.glass,
    required this.glassOpacity,
    required this.child,
    super.key,
  });

  final bool glass;
  final double glassOpacity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final surface = !glass
        ? Material(
            color: Colors.black,
            elevation: 20,
            shadowColor: Colors.black,
            child: child,
          )
        : GlassContainer(
            useOwnLayer: true,
            quality: GlassQuality.premium,
            settings: SpotifinGlass.settings(glassOpacity),
            shape: const LiquidRoundedSuperellipse(borderRadius: 16),
            clipBehavior: Clip.antiAlias,
            child: child,
          );
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) {},
      child: surface,
    );
  }
}

class MobilePlayerBar extends StatelessWidget {
  const MobilePlayerBar({
    required this.track,
    required this.active,
    required this.onOpenPlayer,
    required this.glass,
    required this.glassOpacity,
    this.integrated = false,
    super.key,
  });

  final Track track;
  final ActivePlayback active;
  final VoidCallback onOpenPlayer;
  final bool glass;
  final double glassOpacity;
  final bool integrated;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: active,
      builder: (context, _) {
        final state = active.state;
        final casting = state.destination == PlaybackDestination.cast;
        final content = Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onOpenPlayer,
            child: SafeArea(
              top: false,
              bottom: !glass,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MobileProgress(active: active),
                  LayoutBuilder(
                    builder: (context, constraints) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Artwork(
                            itemId: track.albumId ?? track.id,
                            size: 44,
                            borderRadius: SpotifinRadii.small,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
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
                                const SizedBox(height: 3),
                                Text(
                                  casting && state.connectedDeviceName != null
                                      ? 'Casting to ${state.connectedDeviceName} · ${track.artist}'
                                      : track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: SpotifinColors.textMuted,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (constraints.maxWidth >= 480) ...[
                            const CastButton(),
                            const RemoteDeviceButton(),
                            IconButton(
                              tooltip: 'Previous',
                              onPressed: active.previous,
                              icon: const Icon(Icons.skip_previous_rounded),
                            ),
                          ],
                          SpotifinPlayButton(
                            onPressed: active.toggle,
                            playing: state.playing,
                          ),
                          IconButton(
                            tooltip: 'Next',
                            onPressed: active.next,
                            icon: const Icon(Icons.skip_next_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        if (integrated) return content;
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
          settings: SpotifinGlass.settings(glassOpacity),
          shape: const LiquidRoundedSuperellipse(borderRadius: 16),
          clipBehavior: Clip.antiAlias,
          child: content,
        );
      },
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
                PlayerCollectionLinks(
                  track: track,
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

class DesktopTransport extends StatelessWidget {
  const DesktopTransport({
    required this.active,
    this.showControls = true,
    this.showProgress = true,
    this.large = false,
    super.key,
  });

  final ActivePlayback active;
  final bool showControls;
  final bool showProgress;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: active,
      builder: (context, _) {
        final state = active.state;
        final casting = state.destination == PlaybackDestination.cast;
        final canShuffle = state.capabilities.contains(
          PlaybackCapability.shuffle,
        );
        final canRepeat = state.capabilities.contains(
          PlaybackCapability.repeat,
        );
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (showControls)
              SizedBox(
                height: large ? 68 : 40,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ToggleButton(
                      tooltip: casting && !canShuffle
                          ? 'Stop casting to change shuffle'
                          : 'Shuffle',
                      active: state.shuffle,
                      onPressed: canShuffle ? active.toggleShuffle : () {},
                      icon: Icons.shuffle_rounded,
                      iconSize: large ? 30 : 20,
                    ),
                    IconButton(
                      tooltip: 'Previous',
                      iconSize: large ? 40 : 24,
                      onPressed: active.previous,
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                    _OwnerPlayButton(active: active, size: large ? 56 : 32),
                    IconButton(
                      tooltip: 'Next',
                      iconSize: large ? 40 : 24,
                      onPressed: active.next,
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                    _ToggleButton(
                      tooltip: casting && !canRepeat
                          ? 'Stop casting to change repeat'
                          : 'Repeat',
                      active: state.repeatMode != LoopMode.off,
                      onPressed: canRepeat ? active.cycleRepeat : () {},
                      icon: state.repeatMode == LoopMode.one
                          ? Icons.repeat_one_rounded
                          : Icons.repeat_rounded,
                      iconSize: large ? 30 : 20,
                    ),
                  ],
                ),
              ),
            if (showProgress) _ProgressSlider(active: active),
          ],
        );
      },
    );
  }
}

class _OwnerPlayButton extends StatelessWidget {
  const _OwnerPlayButton({required this.active, required this.size});

  final ActivePlayback active;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: active,
      builder: (context, _) {
        final playing = active.state.playing;
        return IconButton.filled(
          tooltip: playing ? 'Pause' : 'Play',
          style: IconButton.styleFrom(
            backgroundColor: SpotifinColors.text,
            foregroundColor: Colors.black,
            minimumSize: Size.square(size),
            maximumSize: Size.square(size),
            padding: EdgeInsets.zero,
          ),
          onPressed: active.toggle,
          icon: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: size * 0.7,
          ),
        );
      },
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.tooltip,
    required this.active,
    required this.onPressed,
    required this.icon,
    required this.iconSize,
  });

  final String tooltip;
  final bool active;
  final VoidCallback onPressed;
  final IconData icon;
  final double iconSize;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    color: active ? SpotifinColors.accent : SpotifinColors.textMuted,
    onPressed: onPressed,
    icon: Icon(icon, size: iconSize),
  );
}

class _ProgressSlider extends StatelessWidget {
  const _ProgressSlider({required this.active});

  final ActivePlayback active;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: active,
      builder: (context, _) {
        final state = active.state;
        final position = state.position;
        final duration = state.duration ?? Duration.zero;
        return Row(
          children: [
            _TimeLabel(position),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 5,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                ),
                child: PlaybackPositionSlider(active: active),
              ),
            ),
            _TimeLabel(duration),
          ],
        );
      },
    );
  }
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
    required this.active,
    required this.usesSidePanel,
    required this.onOpenQueue,
    required this.onOpenLyrics,
  });

  final ActivePlayback active;
  final bool usesSidePanel;
  final VoidCallback onOpenQueue;
  final VoidCallback onOpenLyrics;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: active,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CastButton(),
            const RemoteDeviceButton(),
            if (usesSidePanel)
              const PlayerPanelTabs()
            else ...[
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
            ],
            const SizedBox(width: SpotifinSpacing.sm),
            if (AirPlayControl.isSupported) const AirPlayControl(),
            Flexible(child: _DesktopVolume(active: active)),
          ],
        );
      },
    );
  }
}

class _DesktopVolume extends StatelessWidget {
  const _DesktopVolume({required this.active});

  static const _iconWidth = 20.0;
  static const _sliderWidth = 144.0;
  static const _minimumSliderWidth = 96.0;

  final ActivePlayback active;

  @override
  Widget build(BuildContext context) {
    final state = active.state;
    return LayoutBuilder(
      builder: (context, constraints) {
        final sliderWidth = (constraints.maxWidth - _iconWidth).clamp(
          0.0,
          _sliderWidth,
        );
        if (sliderWidth < _minimumSliderWidth) return const SizedBox.shrink();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              state.volumeSlider == 0
                  ? Icons.volume_off_rounded
                  : Icons.volume_up_rounded,
              size: _iconWidth,
            ),
            SizedBox(
              width: sliderWidth,
              child: MergeSemantics(
                child: Semantics(
                  label: 'Volume',
                  child: Slider(
                    value: state.volumeSlider.clamp(0.0, 1.0),
                    semanticFormatterCallback: (value) =>
                        '${(value * 100).round()}%',
                    onChanged:
                        state.capabilities.contains(PlaybackCapability.volume)
                        ? active.setVolumeSlider
                        : null,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MobileProgress extends StatelessWidget {
  const _MobileProgress({required this.active});

  final ActivePlayback active;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: active,
      builder: (context, _) {
        final state = active.state;
        final maximum = (state.duration?.inMilliseconds.toDouble() ?? 0).clamp(
          1.0,
          double.infinity,
        );
        return LinearProgressIndicator(
          value: state.position.inMilliseconds.clamp(0, maximum) / maximum,
          minHeight: 2,
        );
      },
    );
  }
}

String _formatTime(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
