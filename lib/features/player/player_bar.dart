import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../platform/airplay_control.dart';
import '../../services/playback/playback_service.dart';
import '../../services/lyrics/lyric_line.dart';
import '../../storage/database.dart';
import '../common/artwork.dart';
import '../common/design_system.dart';
import '../common/glass.dart';
import 'player_bar_controls.dart';
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
            : _showNowPlaying(context, playback, glassEffects, glassOpacity);
        void showLyrics() => useSidePanel
            ? ref.read(playerPanelProvider.notifier).toggleLyrics()
            : _showLyrics(context, track, playback, glassEffects, glassOpacity);
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
  double glassOpacity,
) {
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
    ),
  );
}

void _showLyrics(
  BuildContext context,
  Track track,
  PlaybackService playback,
  bool glass,
  double glassOpacity,
) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 720),
    backgroundColor: glass ? Colors.transparent : null,
    builder: (_) => _LyricsSheet(
      track: track,
      playback: playback,
      glass: glass,
      glassOpacity: glassOpacity,
    ),
  );
}

class _NowPlaying extends ConsumerStatefulWidget {
  const _NowPlaying({
    required this.playback,
    required this.glass,
    required this.glassOpacity,
  });
  final PlaybackService playback;
  final bool glass;
  final double glassOpacity;

  @override
  ConsumerState<_NowPlaying> createState() => _NowPlayingState();
}

class _NowPlayingState extends ConsumerState<_NowPlaying> {
  var _showLyrics = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.playback,
    builder: (context, _) {
      final playback = widget.playback;
      final track = playback.currentTrack;
      if (track == null) return const SizedBox.shrink();
      final queue = playback.queue;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: .92,
        minChildSize: .55,
        builder: (context, controller) => _NowPlayingSurface(
          glass: widget.glass,
          glassOpacity: widget.glassOpacity,
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
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: _showLyrics
                                ? ClipRRect(
                                    key: const ValueKey('lyrics'),
                                    borderRadius: BorderRadius.circular(
                                      SpotifinRadii.card,
                                    ),
                                    child: ColoredBox(
                                      color: SpotifinColors.raised,
                                      child: _LyricsContent(
                                        track: track,
                                        playback: playback,
                                      ),
                                    ),
                                  )
                                : Artwork(
                                    key: const ValueKey('artwork'),
                                    itemId: track.albumId ?? track.id,
                                    size: 420,
                                    borderRadius: SpotifinRadii.card,
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
                    StreamBuilder<Duration>(
                      stream: playback.player.positionStream,
                      builder: (context, snapshot) {
                        final position = snapshot.data ?? Duration.zero;
                        final duration =
                            playback.player.duration ?? Duration.zero;
                        final max = duration.inMilliseconds.toDouble().clamp(
                          1.0,
                          double.infinity,
                        );
                        return Column(
                          children: [
                            Slider(
                              value: position.inMilliseconds.toDouble().clamp(
                                0,
                                max,
                              ),
                              max: max,
                              onChanged: (value) => playback.seek(
                                Duration(milliseconds: value.round()),
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _time(position),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                Text(
                                  _time(duration),
                                  style: Theme.of(context).textTheme.bodySmall,
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
                          tooltip: 'Shuffle',
                          color: playback.shuffle
                              ? SpotifinColors.accent
                              : null,
                          onPressed: playback.toggleShuffle,
                          icon: const Icon(Icons.shuffle_rounded),
                        ),
                        IconButton(
                          iconSize: 42,
                          onPressed: playback.previous,
                          icon: const Icon(Icons.skip_previous_rounded),
                        ),
                        SpotifinPlayButton(
                          onPressed: playback.toggle,
                          playing: playback.playing,
                          large: true,
                        ),
                        IconButton(
                          iconSize: 42,
                          onPressed: playback.next,
                          icon: const Icon(Icons.skip_next_rounded),
                        ),
                        IconButton(
                          tooltip: 'Repeat',
                          color: playback.loopMode == LoopMode.off
                              ? null
                              : SpotifinColors.accent,
                          onPressed: playback.cycleRepeat,
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
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                setState(() => _showLyrics = !_showLyrics),
                            style: _showLyrics
                                ? OutlinedButton.styleFrom(
                                    foregroundColor: SpotifinColors.accent,
                                    backgroundColor: SpotifinColors.accent
                                        .withValues(alpha: .12),
                                    side: const BorderSide(
                                      color: SpotifinColors.accent,
                                    ),
                                  )
                                : null,
                            icon: Icon(
                              _showLyrics
                                  ? Icons.lyrics_rounded
                                  : Icons.lyrics_outlined,
                            ),
                            label: const Text('Lyrics'),
                          ),
                        ),
                        if (AirPlayControl.isSupported) ...[
                          const SizedBox(width: SpotifinSpacing.sm),
                          const AirPlayControl(),
                        ],
                        const SizedBox(width: SpotifinSpacing.sm),
                        const RemoteDeviceButton(),
                      ],
                    ),
                    const SizedBox(height: 30),
                    Text(
                      'Queue',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SpotifinSpacing.sm,
                ),
                sliver: SliverReorderableList(
                  itemCount: queue.length,
                  onReorderItem: playback.reorder,
                  itemBuilder: (context, index) {
                    final item = queue[index];
                    return ReorderableDelayedDragStartListener(
                      key: ValueKey('$index-${item.id}'),
                      index: index,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        horizontalTitleGap: SpotifinSpacing.sm,
                        selected: index == playback.currentIndex,
                        selectedTileColor: SpotifinColors.interactive,
                        selectedColor: SpotifinColors.accent,
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
                          onPressed: () => playback.removeAt(index),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 36)),
            ],
          ),
        ),
      );
    },
  );

  static String _time(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _LyricsSheet extends ConsumerWidget {
  const _LyricsSheet({
    required this.track,
    required this.playback,
    required this.glass,
    required this.glassOpacity,
  });
  final Track track;
  final PlaybackService playback;
  final bool glass;
  final double glassOpacity;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _SheetSurface(
    glass: glass,
    glassOpacity: glassOpacity,
    child: SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .82,
        child: _LyricsContent(track: track, playback: playback),
      ),
    ),
  );
}

class _LyricsContent extends ConsumerStatefulWidget {
  const _LyricsContent({required this.track, required this.playback});

  final Track track;
  final PlaybackService playback;

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
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 50),
              itemCount: lines.length,
              itemBuilder: (context, index) {
                final line = lines[index];
                return InkWell(
                  onTap: line.start == null
                      ? null
                      : () => widget.playback.seek(line.start!),
                  borderRadius: BorderRadius.circular(SpotifinRadii.small),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      line.text,
                      style: Theme.of(context).textTheme.headlineSmall
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

class _SheetSurface extends StatelessWidget {
  const _SheetSurface({
    required this.glass,
    required this.glassOpacity,
    required this.child,
  });

  final bool glass;
  final double glassOpacity;
  final Widget child;

  @override
  Widget build(BuildContext context) => glass
      ? _glassSheet(child, glassOpacity)
      : ColoredBox(color: SpotifinColors.surface, child: child);
}

Widget _glassSheet(Widget child, double opacity) => GlassContainer(
  useOwnLayer: true,
  quality: GlassQuality.standard,
  settings: SpotifinGlass.settings(opacity),
  shape: const LiquidRoundedSuperellipse(borderRadius: 24),
  clipBehavior: Clip.antiAlias,
  child: child,
);
