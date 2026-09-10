import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../app/providers.dart';
import '../../app/state/player_panel_controller.dart';
import '../../app/theme.dart';
import '../../services/lyrics/lyric_line.dart';
import '../../services/playback/playback_service.dart';
import '../../storage/database.dart';
import '../common/artwork.dart';
import '../common/design_system.dart';

class PlayerSidePanel extends ConsumerWidget {
  const PlayerSidePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackProvider);
    final view = ref.watch(playerPanelProvider);
    return Material(
      color: SpotifinColors.surface,
      child: Column(
        children: [
          _PanelHeader(view: view),
          Expanded(
            child: ListenableBuilder(
              listenable: playback,
              builder: (context, _) {
                final track = playback.currentTrack;
                if (track == null) {
                  return const SpotifinEmptyState(
                    icon: Icons.music_note_rounded,
                    title: 'Nothing playing',
                  );
                }
                return switch (view) {
                  PlayerPanelView.queue => _QueuePanel(playback: playback),
                  PlayerPanelView.lyrics => _LyricsPanel(
                    track: track,
                    playback: playback,
                  ),
                  _ => _PlayerPanel(track: track, playback: playback),
                };
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelHeader extends ConsumerWidget {
  const _PanelHeader({required this.view});

  final PlayerPanelView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
    child: Row(
      children: [
        _PanelTab(
          label: 'Player',
          icon: Icons.album_rounded,
          selected: view == PlayerPanelView.player,
          onPressed: () => ref
              .read(playerPanelProvider.notifier)
              .show(PlayerPanelView.player),
        ),
        _PanelTab(
          label: 'Queue',
          icon: Icons.queue_music_rounded,
          selected: view == PlayerPanelView.queue,
          onPressed: () => ref
              .read(playerPanelProvider.notifier)
              .show(PlayerPanelView.queue),
        ),
        _PanelTab(
          label: 'Lyrics',
          icon: Icons.lyrics_outlined,
          selected: view == PlayerPanelView.lyrics,
          onPressed: () => ref
              .read(playerPanelProvider.notifier)
              .show(PlayerPanelView.lyrics),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Close',
          onPressed: ref.read(playerPanelProvider.notifier).close,
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    ),
  );
}

class _PanelTab extends StatelessWidget {
  const _PanelTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    isSelected: selected,
    color: SpotifinColors.textMuted,
    selectedIcon: Icon(icon, color: SpotifinColors.accent),
    onPressed: onPressed,
    icon: Icon(icon),
  );
}

class _PlayerPanel extends StatelessWidget {
  const _PlayerPanel({required this.track, required this.playback});

  final Track track;
  final PlaybackService playback;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
    children: [
      AspectRatio(
        aspectRatio: 1,
        child: Artwork(
          itemId: track.id,
          size: 420,
          borderRadius: SpotifinRadii.card,
        ),
      ),
      const SizedBox(height: SpotifinSpacing.lg),
      Text(
        track.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: SpotifinSpacing.xxs),
      Text(track.artist, style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: SpotifinSpacing.md),
      _PanelProgress(playback: playback),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ActiveControl(
            tooltip: 'Shuffle',
            active: playback.shuffle,
            onPressed: playback.toggleShuffle,
            icon: Icons.shuffle_rounded,
          ),
          IconButton(
            tooltip: 'Previous',
            iconSize: 32,
            onPressed: playback.previous,
            icon: const Icon(Icons.skip_previous_rounded),
          ),
          SpotifinPlayButton(
            onPressed: playback.toggle,
            playing: playback.playing,
            large: true,
          ),
          IconButton(
            tooltip: 'Next',
            iconSize: 32,
            onPressed: playback.next,
            icon: const Icon(Icons.skip_next_rounded),
          ),
          _ActiveControl(
            tooltip: 'Repeat',
            active: playback.loopMode != LoopMode.off,
            onPressed: playback.cycleRepeat,
            icon: playback.loopMode == LoopMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
          ),
        ],
      ),
    ],
  );
}

class _ActiveControl extends StatelessWidget {
  const _ActiveControl({
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
    icon: Icon(icon),
  );
}

class _PanelProgress extends StatelessWidget {
  const _PanelProgress({required this.playback});

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
      return Column(
        children: [
          Slider(
            value: position.inMilliseconds.toDouble().clamp(0.0, maximum),
            max: maximum,
            onChanged: (value) =>
                playback.seek(Duration(milliseconds: value.round())),
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
  );
}

class _QueuePanel extends StatelessWidget {
  const _QueuePanel({required this.playback});

  final PlaybackService playback;

  @override
  Widget build(BuildContext context) => ReorderableListView.builder(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 112),
    itemCount: playback.queue.length,
    onReorderItem: playback.reorder,
    itemBuilder: (context, index) {
      final track = playback.queue[index];
      return ListTile(
        key: ValueKey('$index-${track.id}'),
        selected: index == playback.currentIndex,
        selectedColor: SpotifinColors.accent,
        selectedTileColor: SpotifinColors.interactive,
        leading: Artwork(
          itemId: track.id,
          size: 44,
          borderRadius: SpotifinRadii.small,
        ),
        title: Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          track.artist,
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
  );
}

class _LyricsPanel extends ConsumerStatefulWidget {
  const _LyricsPanel({required this.track, required this.playback});

  final Track track;
  final PlaybackService playback;

  @override
  ConsumerState<_LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends ConsumerState<_LyricsPanel> {
  late Future<List<LyricLine>> _lyrics;

  @override
  void initState() {
    super.initState();
    _lyrics = _load();
  }

  @override
  void didUpdateWidget(covariant _LyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) _lyrics = _load();
  }

  Future<List<LyricLine>> _load() {
    final session = ref.read(appControllerProvider).session;
    if (session == null) return Future.value(const []);
    return ref.read(lyricsProvider).find(session, widget.track);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<LyricLine>>(
    future: _lyrics,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      final lines = snapshot.data ?? const [];
      if (lines.isEmpty) {
        return const SpotifinEmptyState(
          icon: Icons.lyrics_outlined,
          title: 'No lyrics found',
        );
      }
      return StreamBuilder<Duration>(
        stream: widget.playback.player.positionStream,
        builder: (context, positionSnapshot) {
          final active = _activeLine(
            lines,
            positionSnapshot.data ?? Duration.zero,
          );
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 112),
            itemCount: lines.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                lines[index].text,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: index == active
                      ? SpotifinColors.text
                      : SpotifinColors.textMuted,
                ),
              ),
            ),
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

String _time(Duration value) {
  final minutes = value.inMinutes;
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
