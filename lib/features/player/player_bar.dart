import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../platform/airplay_control.dart';
import '../../services/playback/playback_service.dart';
import '../../services/lyrics/lyric_line.dart';
import '../../storage/database.dart';
import '../common/artwork.dart';
import '../common/design_system.dart';
import 'player_bar_controls.dart';

class PlayerBar extends ConsumerWidget {
  const PlayerBar({super.key});

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
        void showPlayer() => useSidePanel
            ? ref.read(playerPanelProvider.notifier).togglePlayer()
            : _showNowPlaying(context, playback);

        void showQueue() => useSidePanel
            ? ref.read(playerPanelProvider.notifier).toggleQueue()
            : _showNowPlaying(context, playback);
        void showLyrics() => useSidePanel
            ? ref.read(playerPanelProvider.notifier).toggleLyrics()
            : _showLyrics(context, track, playback);
        return LayoutBuilder(
          builder: (context, constraints) =>
              constraints.maxWidth >= SpotifinBreakpoints.rail
              ? DesktopPlayerBar(
                  track: track,
                  playback: playback,
                  onOpenPlayer: showPlayer,
                  onOpenQueue: showQueue,
                  onOpenLyrics: showLyrics,
                )
              : MobilePlayerBar(
                  track: track,
                  playback: playback,
                  onOpenPlayer: showPlayer,
                ),
        );
      },
    );
  }
}

void _showNowPlaying(BuildContext context, PlaybackService playback) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 720),
    backgroundColor: SpotifinColors.surface,
    builder: (_) => _NowPlaying(playback: playback),
  );
}

void _showLyrics(BuildContext context, Track track, PlaybackService playback) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 720),
    builder: (_) => _LyricsSheet(track: track, playback: playback),
  );
}

class _NowPlaying extends ConsumerWidget {
  const _NowPlaying({required this.playback});
  final PlaybackService playback;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListenableBuilder(
    listenable: playback,
    builder: (context, _) {
      final track = playback.currentTrack;
      if (track == null) return const SizedBox.shrink();
      final queue = playback.queue;
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: .92,
        minChildSize: .55,
        builder: (context, controller) => DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.center,
              colors: [SpotifinColors.raised, SpotifinColors.surface],
            ),
          ),
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
                          child: Artwork(
                            itemId: track.albumId ?? track.id,
                            size: 420,
                            borderRadius: SpotifinRadii.card,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      track.name,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    Text(
                      track.artist,
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
                            onPressed: () => showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              useSafeArea: true,
                              constraints: const BoxConstraints(maxWidth: 720),
                              builder: (_) => _LyricsSheet(
                                track: track,
                                playback: playback,
                              ),
                            ),
                            icon: const Icon(Icons.lyrics_outlined),
                            label: const Text('Lyrics'),
                          ),
                        ),
                        if (AirPlayControl.isSupported) ...[
                          const SizedBox(width: SpotifinSpacing.sm),
                          const AirPlayControl(),
                        ],
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
  const _LyricsSheet({required this.track, required this.playback});
  final Track track;
  final PlaybackService playback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(appControllerProvider).session;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .82,
        child: session == null
            ? const Center(child: Text('Lyrics are unavailable offline.'))
            : FutureBuilder<List<LyricLine>>(
                future: ref.read(lyricsProvider).find(session, track),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final lines = snapshot.data ?? const [];
                  if (lines.isEmpty) {
                    return const Center(child: Text('No lyrics found'));
                  }
                  return StreamBuilder<Duration>(
                    stream: playback.player.positionStream,
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
                                : () => playback.seek(line.start!),
                            borderRadius: BorderRadius.circular(
                              SpotifinRadii.small,
                            ),
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
              ),
      ),
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
