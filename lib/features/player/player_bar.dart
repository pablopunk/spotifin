import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../platform/airplay_control.dart';
import '../../services/cast/cast_controller.dart';
import '../../services/playback/playback_service.dart';
import '../../services/lyrics/lyric_line.dart';
import '../../storage/database.dart';
import '../common/artwork.dart';
import '../common/design_system.dart';
import '../common/glass.dart';
import 'cast_button.dart';
import 'history_list.dart';
import 'player_bar_controls.dart';
import 'player_artwork_carousel.dart';
import 'player_collection_links.dart';
import 'remote_devices.dart';

class PlayerBar extends ConsumerWidget {
  const PlayerBar({this.integratedMobile = false, super.key});

  final bool integratedMobile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackProvider);
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) {
        final track = playback.currentTrack;
        if (track == null) return const SizedBox.shrink();
        final useSidePanel =
            MediaQuery.sizeOf(context).width >= SpotifinBreakpoints.playerPanel;
        final glassEffects = ref.watch(glassEffectsProvider);
        final glassOpacity = ref.watch(glassOpacityProvider);
        void showPlayer() => useSidePanel
            ? ref.read(playerPanelProvider.notifier).togglePlayer()
            : _showNowPlaying(context, playback, glassEffects, glassOpacity);

        void showQueue() => useSidePanel
            ? ref.read(playerPanelProvider.notifier).toggleQueue()
            : _showNowPlaying(
                context,
                playback,
                glassEffects,
                glassOpacity,
                initialDetailsTab: 1,
              );
        void showLyrics() => useSidePanel
            ? ref.read(playerPanelProvider.notifier).toggleLyrics()
            : _showNowPlaying(
                context,
                playback,
                glassEffects,
                glassOpacity,
                initialDetailsTab: 0,
              );
        return LayoutBuilder(
          builder: (context, constraints) =>
              constraints.maxWidth >= SpotifinBreakpoints.rail
              ? DesktopPlayerBar(
                  track: track,
                  playback: playback,
                  onOpenPlayer: showPlayer,
                  onOpenQueue: showQueue,
                  onOpenLyrics: showLyrics,
                  glass: glassEffects,
                  glassOpacity: glassOpacity,
                )
              : MobilePlayerBar(
                  track: track,
                  playback: playback,
                  onOpenPlayer: showPlayer,
                  glass: glassEffects,
                  glassOpacity: glassOpacity,
                  integrated: integratedMobile,
                ),
        );
      },
    );
  }
}

void _showNowPlaying(
  BuildContext context,
  PlaybackService playback,
  bool glass,
  double glassOpacity, {
  int initialDetailsTab = 1,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 720),
    backgroundColor: glass ? Colors.transparent : SpotifinColors.surface,
    builder: (_) => _NowPlaying(
      playback: playback,
      glass: glass,
      glassOpacity: glassOpacity,
      initialDetailsTab: initialDetailsTab,
    ),
  );
}

class _NowPlaying extends ConsumerStatefulWidget {
  const _NowPlaying({
    required this.playback,
    required this.glass,
    required this.glassOpacity,
    required this.initialDetailsTab,
  });
  final PlaybackService playback;
  final bool glass;
  final double glassOpacity;
  final int initialDetailsTab;

  @override
  ConsumerState<_NowPlaying> createState() => _NowPlayingState();
}

class _NowPlayingState extends ConsumerState<_NowPlaying> {
  late int _detailsTab = widget.initialDetailsTab;

  @override
  Widget build(BuildContext context) {
    final cast = ref.watch(castControllerProvider);
    return ListenableBuilder(
      listenable: cast,
      builder: (context, _) => ListenableBuilder(
        listenable: widget.playback,
        builder: (context, _) {
          final playback = widget.playback;
          final casting = cast.isCasting;
          final track = casting
              ? (cast.remoteTrack ?? playback.currentTrack)
              : playback.currentTrack;
          if (track == null) return const SizedBox.shrink();
          final fullQueue = casting ? cast.castQueue : playback.queue;
          final queue = casting
              ? cast.castQueue
                    .skip(cast.remoteIndex.clamp(0, cast.castQueue.length))
                    .toList(growable: false)
              : playback.upcomingQueue;
          final currentIndex = casting
              ? cast.remoteIndex
              : playback.currentIndex;
          Future<void> seekTo(Duration position) =>
              casting ? cast.seek(position) : playback.seek(position);
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: .92,
            minChildSize: .55,
            builder: (context, controller) => _NowPlayingSurface(
              glass: widget.glass,
              glassOpacity: widget.glassOpacity,
              child: DefaultTabController(
                initialIndex: _detailsTab,
                length: 3,
                child: CustomScrollView(
                  controller: controller,
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(28, 12, 28, 0),
                      sliver: SliverList.list(
                        children: [
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: SpotifinColors.borderStrong,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          if (casting)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _CastingBanner(
                                deviceName:
                                    cast.connectedDeviceName ?? 'Chromecast',
                                onStop: cast.disconnect,
                              ),
                            ),
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 640),
                              child: LayoutBuilder(
                                builder: (context, constraints) => SizedBox(
                                  height: constraints.maxWidth.clamp(0, 420),
                                  child: PlayerArtworkCarousel(
                                    tracks: fullQueue,
                                    currentIndex: currentIndex,
                                    onTrackChanged: casting
                                        ? cast.playIndex
                                        : playback.playQueueIndex,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            track.name,
                            style: Theme.of(context).textTheme.headlineLarge,
                          ),
                          PlayerCollectionLinks(
                            track: track,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: SpotifinColors.textMuted),
                          ),
                          const SizedBox(height: 18),
                          if (casting)
                            _CastPositionSlider(cast: cast)
                          else
                            StreamBuilder<Duration>(
                              stream: playback.player.positionStream,
                              builder: (context, snapshot) {
                                final position = snapshot.data ?? Duration.zero;
                                final duration =
                                    playback.player.duration ?? Duration.zero;
                                final max = duration.inMilliseconds
                                    .toDouble()
                                    .clamp(1.0, double.infinity);
                                return Column(
                                  children: [
                                    Slider(
                                      value: position.inMilliseconds
                                          .toDouble()
                                          .clamp(0, max),
                                      max: max,
                                      onChanged: (value) => playback.seek(
                                        Duration(milliseconds: value.round()),
                                      ),
                                    ),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _time(position),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                        Text(
                                          _time(duration),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                    ),
                                  ],
                                );
                              },
                            ),
                          Wrap(
                            alignment: WrapAlignment.spaceEvenly,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: SpotifinSpacing.xs,
                            children: [
                              IconButton(
                                tooltip: casting
                                    ? 'Stop casting to change shuffle'
                                    : 'Shuffle',
                                color: playback.shuffle
                                    ? SpotifinColors.accent
                                    : null,
                                onPressed: casting
                                    ? null
                                    : playback.toggleShuffle,
                                icon: const Icon(Icons.shuffle_rounded),
                              ),
                              IconButton(
                                iconSize: 42,
                                tooltip: 'Previous',
                                onPressed: casting
                                    ? cast.previous
                                    : playback.previous,
                                icon: const Icon(Icons.skip_previous_rounded),
                              ),
                              SpotifinPlayButton(
                                onPressed: casting
                                    ? cast.toggle
                                    : playback.toggle,
                                playing: casting
                                    ? cast.remotePlaying
                                    : playback.playing,
                                large: true,
                              ),
                              IconButton(
                                iconSize: 42,
                                tooltip: 'Next',
                                onPressed: casting ? cast.next : playback.next,
                                icon: const Icon(Icons.skip_next_rounded),
                              ),
                              IconButton(
                                tooltip: casting
                                    ? 'Stop casting to change repeat'
                                    : 'Repeat',
                                color: playback.loopMode == LoopMode.off
                                    ? null
                                    : SpotifinColors.accent,
                                onPressed: casting
                                    ? null
                                    : playback.cycleRepeat,
                                icon: Icon(
                                  playback.loopMode == LoopMode.one
                                      ? Icons.repeat_one_rounded
                                      : Icons.repeat_rounded,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              const Spacer(),
                              if (AirPlayControl.isSupported) ...[
                                const AirPlayControl(),
                                const SizedBox(width: SpotifinSpacing.sm),
                              ],
                              const CastButton(),
                              const SizedBox(width: SpotifinSpacing.sm),
                              const RemoteDeviceButton(),
                              const Spacer(),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: SpotifinTabBar(
                                  labels: const ['Lyrics', 'Queue', 'History'],
                                  onTap: (index) =>
                                      setState(() => _detailsTab = index),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                    if (_detailsTab == 0)
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: SpotifinSpacing.sm,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              SpotifinRadii.card,
                            ),
                            child: ColoredBox(
                              color: SpotifinColors.raised,
                              child: _LyricsContent(
                                track: track,
                                playback: playback,
                                embedded: true,
                                onSeek: casting ? seekTo : null,
                              ),
                            ),
                          ),
                        ),
                      )
                    else if (_detailsTab == 1)
                      if (casting)
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: SpotifinSpacing.sm,
                          ),
                          sliver: SliverList.list(
                            children: [
                              const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                child: Text(
                                  'Casting from this queue. Queue editing resumes after disconnect.',
                                ),
                              ),
                              for (
                                var mobileIndex = 0;
                                mobileIndex < queue.length;
                                mobileIndex++
                              )
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  horizontalTitleGap: SpotifinSpacing.sm,
                                  selected: mobileIndex == 0,
                                  selectedTileColor: SpotifinColors.interactive,
                                  selectedColor: SpotifinColors.accent,
                                  hoverColor: SpotifinColors.hover,
                                  onTap: () => cast.playIndex(
                                    cast.remoteIndex + mobileIndex,
                                  ),
                                  leading: Artwork(
                                    itemId:
                                        queue[mobileIndex].albumId ??
                                        queue[mobileIndex].id,
                                    size: 42,
                                    borderRadius: SpotifinRadii.small,
                                  ),
                                  title: Text(
                                    queue[mobileIndex].name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    queue[mobileIndex].artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: SpotifinSpacing.sm,
                          ),
                          sliver: SliverReorderableList(
                            itemCount: queue.length,
                            onReorderItem: playback.reorderUpcoming,
                            itemBuilder: (context, index) {
                              final item = queue[index];
                              return ReorderableDelayedDragStartListener(
                                key: ValueKey('$index-${item.id}'),
                                index: index,
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  horizontalTitleGap: SpotifinSpacing.sm,
                                  selected:
                                      playback.currentIndex != null &&
                                      index == 0,
                                  selectedTileColor: SpotifinColors.interactive,
                                  selectedColor: SpotifinColors.accent,
                                  hoverColor: SpotifinColors.hover,
                                  onTap: () =>
                                      playback.playUpcomingIndex(index),
                                  leading: Artwork(
                                    itemId: item.albumId ?? item.id,
                                    size: 42,
                                    borderRadius: SpotifinRadii.small,
                                  ),
                                  title: Text(
                                    item.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    item.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: IconButton(
                                    tooltip: 'Remove from queue',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints.tightFor(
                                      width: 40,
                                      height: 40,
                                    ),
                                    onPressed: () =>
                                        playback.removeUpcomingAt(index),
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                ),
                              );
                            },
                          ),
                        )
                    else
                      const SliverToBoxAdapter(
                        child: SizedBox(height: 480, child: HistoryList()),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 36)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static String _time(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _CastingBanner extends StatelessWidget {
  const _CastingBanner({required this.deviceName, required this.onStop});

  final String deviceName;
  final Future<void> Function() onStop;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: SpotifinColors.interactive,
      borderRadius: BorderRadius.circular(SpotifinRadii.small),
    ),
    child: Row(
      children: [
        const Icon(Icons.cast_connected_rounded, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Casting to $deviceName',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextButton(onPressed: () => onStop(), child: const Text('Stop')),
      ],
    ),
  );
}

class _CastPositionSlider extends StatelessWidget {
  const _CastPositionSlider({required this.cast});

  final CastController cast;

  @override
  Widget build(BuildContext context) {
    final position = cast.remotePosition;
    final duration = cast.remoteDuration ?? Duration.zero;
    final max = duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);
    return Column(
      children: [
        Slider(
          value: position.inMilliseconds.toDouble().clamp(0, max),
          max: max,
          onChanged: (value) =>
              cast.seek(Duration(milliseconds: value.round())),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _NowPlayingState._time(position),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              _NowPlayingState._time(duration),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }
}

class _LyricsContent extends ConsumerStatefulWidget {
  const _LyricsContent({
    required this.track,
    required this.playback,
    this.embedded = false,
    this.onSeek,
  });

  final Track track;
  final PlaybackService playback;
  final bool embedded;
  final Future<void> Function(Duration)? onSeek;

  @override
  ConsumerState<_LyricsContent> createState() => _LyricsContentState();
}

class _LyricsContentState extends ConsumerState<_LyricsContent> {
  Object? _session;
  String? _trackId;
  Future<List<LyricLine>>? _lyrics;

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(appControllerProvider).session;
    if (session == null) {
      return const Center(child: Text('Lyrics are unavailable offline.'));
    }
    if (_session != session || _trackId != widget.track.id) {
      _session = session;
      _trackId = widget.track.id;
      _lyrics = ref.read(lyricsProvider).find(session, widget.track);
    }
    return FutureBuilder<List<LyricLine>>(
      future: _lyrics,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return SpotifinEmptyState(
            icon: Icons.sync_problem_rounded,
            title: 'Could not load lyrics',
            message: snapshot.error.toString(),
          );
        }
        final lines = snapshot.data ?? const [];
        if (lines.isEmpty) return const Center(child: Text('No lyrics found'));
        return StreamBuilder<Duration>(
          stream: widget.playback.player.positionStream,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            final active = _activeLine(lines, position);
            return ListView.builder(
              shrinkWrap: widget.embedded,
              physics: widget.embedded
                  ? const NeverScrollableScrollPhysics()
                  : null,
              primary: !widget.embedded,
              padding: widget.embedded
                  ? const EdgeInsets.symmetric(horizontal: 20, vertical: 18)
                  : const EdgeInsets.fromLTRB(24, 30, 24, 50),
              itemCount: lines.length,
              itemBuilder: (context, index) {
                final line = lines[index];
                return InkWell(
                  onTap: line.start == null
                      ? null
                      : () => widget.onSeek == null
                            ? widget.playback.seek(line.start!)
                            : widget.onSeek!(line.start!),
                  borderRadius: BorderRadius.circular(SpotifinRadii.small),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: widget.embedded ? 6 : 8,
                    ),
                    child: Text(
                      line.text,
                      style:
                          (widget.embedded
                                  ? Theme.of(context).textTheme.titleMedium
                                  : Theme.of(context).textTheme.headlineSmall)
                              ?.copyWith(
                                color: index == active
                                    ? SpotifinColors.accent
                                    : SpotifinColors.textMuted,
                                fontWeight: index == active
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  int _activeLine(List<LyricLine> lines, Duration position) {
    var result = -1;
    for (var index = 0; index < lines.length; index++) {
      final start = lines[index].start;
      if (start != null && start <= position) result = index;
    }
    return result;
  }
}

class _NowPlayingSurface extends StatelessWidget {
  const _NowPlayingSurface({
    required this.glass,
    required this.glassOpacity,
    required this.child,
  });

  final bool glass;
  final double glassOpacity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (glass) return _glassSheet(child, glassOpacity);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.center,
          colors: [SpotifinColors.raised, SpotifinColors.surface],
        ),
      ),
      child: child,
    );
  }
}

Widget _glassSheet(Widget child, double opacity) => GlassContainer(
  useOwnLayer: true,
  quality: GlassQuality.premium,
  settings: SpotifinGlass.settings(opacity),
  shape: const LiquidRoundedSuperellipse(borderRadius: 24),
  clipBehavior: Clip.antiAlias,
  child: child,
);
