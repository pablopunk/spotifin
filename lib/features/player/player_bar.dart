import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../services/playback/playback_service.dart';
import '../common/artwork.dart';

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
        return Material(
          color: SpotifinColors.raised,
          child: InkWell(
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: SpotifinColors.surface,
              builder: (_) => _NowPlaying(playback: playback),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StreamBuilder<Duration>(
                    stream: playback.player.positionStream,
                    builder: (context, snapshot) {
                      final duration = playback.player.duration;
                      final maximum = duration?.inMilliseconds.toDouble() ?? 1;
                      return LinearProgressIndicator(
                        value:
                            (snapshot.data?.inMilliseconds ?? 0).clamp(
                              0,
                              maximum,
                            ) /
                            maximum,
                        minHeight: 2,
                      );
                    },
                  ),
                  ListTile(
                    leading: Artwork(itemId: track.id, size: 48),
                    title: Text(
                      track.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Previous',
                          onPressed: playback.previous,
                          icon: const Icon(Icons.skip_previous_rounded),
                        ),
                        IconButton(
                          tooltip: playback.playing ? 'Pause' : 'Play',
                          onPressed: playback.toggle,
                          icon: Icon(
                            playback.playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
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
      },
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.playback});
  final PlaybackService playback;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: playback,
    builder: (context, _) {
      final track = playback.currentTrack;
      if (track == null) return const SizedBox.shrink();
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: .92,
        minChildSize: .55,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 36),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
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
                  child: Artwork(itemId: track.id, size: 420, borderRadius: 24),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(track.name, style: Theme.of(context).textTheme.headlineSmall),
            Text(
              track.artist,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: Colors.white60),
            ),
            const SizedBox(height: 18),
            StreamBuilder<Duration>(
              stream: playback.player.positionStream,
              builder: (context, snapshot) {
                final position = snapshot.data ?? Duration.zero;
                final duration = playback.player.duration ?? Duration.zero;
                final max = duration.inMilliseconds.toDouble().clamp(
                  1.0,
                  double.infinity,
                );
                return Column(
                  children: [
                    Slider(
                      value: position.inMilliseconds.toDouble().clamp(0, max),
                      max: max,
                      onChanged: (value) =>
                          playback.seek(Duration(milliseconds: value.round())),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [Text(_time(position)), Text(_time(duration))],
                    ),
                  ],
                );
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  tooltip: 'Shuffle',
                  color: playback.shuffle ? SpotifinColors.accent : null,
                  onPressed: playback.toggleShuffle,
                  icon: const Icon(Icons.shuffle_rounded),
                ),
                IconButton(
                  iconSize: 42,
                  onPressed: playback.previous,
                  icon: const Icon(Icons.skip_previous_rounded),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(20),
                  ),
                  onPressed: playback.toggle,
                  child: Icon(
                    playback.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 38,
                  ),
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
            const SizedBox(height: 30),
            Text('Queue', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: playback.queue.length,
              onReorderItem: playback.reorder,
              itemBuilder: (context, index) {
                final item = playback.queue[index];
                return ListTile(
                  key: ValueKey('$index-${item.id}'),
                  selected: index == playback.currentIndex,
                  leading: Artwork(itemId: item.id, size: 42),
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
                    onPressed: () => playback.removeAt(index),
                    icon: const Icon(Icons.close_rounded),
                  ),
                );
              },
            ),
          ],
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
