import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
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
    final panels = ref.watch(playerPanelProvider);
    final panelController = ref.read(playerPanelProvider.notifier);
    return Material(
      color: SpotifinColors.surface,
      child: Column(
        children: [
          _PanelHeader(panels: panels),
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
                return Column(
                  children: [
                    if (panels.player)
                      Expanded(
                        flex: panels.queue && panels.lyrics ? 2 : 1,
                        child: _PanelSection(
                          title: 'Now playing',
                          onClose: panelController.togglePlayer,
                          child: _PlayerPanel(track: track, playback: playback),
                        ),
                      ),
                    if (panels.lyrics) ...[
                      if (panels.player) const Divider(height: 1),
                      Expanded(
                        child: _PanelSection(
                          title: 'Lyrics',
                          onClose: panelController.toggleLyrics,
                          child: _LyricsPanel(track: track, playback: playback),
                        ),
                      ),
                    ],
                    if (panels.queue) ...[
                      if (panels.player || panels.lyrics)
                        const Divider(height: 1),
                      Expanded(
                        child: _PanelSection(
                          title: 'Queue',
                          onClose: panelController.toggleQueue,
                          child: _QueuePanel(playback: playback),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelHeader extends ConsumerWidget {
  const _PanelHeader({required this.panels});

  final PlayerPanelState panels;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
    child: Row(
      children: [
        _PanelTab(
          label: 'Player',
          icon: Icons.album_rounded,
          selected: panels.player,
          onPressed: ref.read(playerPanelProvider.notifier).togglePlayer,
        ),
        _PanelTab(
          label: 'Lyrics',
          icon: Icons.lyrics_outlined,
          selected: panels.lyrics,
          onPressed: ref.read(playerPanelProvider.notifier).toggleLyrics,
        ),
        _PanelTab(
          label: 'Queue',
          icon: Icons.queue_music_rounded,
          selected: panels.queue,
          onPressed: ref.read(playerPanelProvider.notifier).toggleQueue,
        ),
        const Spacer(),
      ],
    ),
  );
}

class _PanelSection extends StatelessWidget {
  const _PanelSection({
    required this.title,
    required this.onClose,
    required this.child,
  });

  final String title;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleSmall),
            ),
            IconButton(
              tooltip: 'Close $title',
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
              iconSize: 17,
              color: SpotifinColors.textMuted,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
      Expanded(child: child),
    ],
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
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    label: Text(label),
    style: TextButton.styleFrom(
      foregroundColor: selected
          ? SpotifinColors.accent
          : SpotifinColors.textMuted,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(0, 36),
      visualDensity: VisualDensity.compact,
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );
}

class _PlayerPanel extends StatelessWidget {
  const _PlayerPanel({required this.track, required this.playback});

  final Track track;
  final PlaybackService playback;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
    child: Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest.shortestSide;
              return Align(
                alignment: Alignment.bottomCenter,
                child: Artwork(
                  itemId: track.albumId ?? track.id,
                  size: size,
                  borderRadius: SpotifinRadii.card,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: SpotifinSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            track.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: SpotifinSpacing.xxs),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            track.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: SpotifinSpacing.xs),
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
    ),
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
    buildDefaultDragHandles: false,
    itemCount: playback.queue.length,
    onReorderItem: playback.reorder,
    itemBuilder: (context, index) {
      final track = playback.queue[index];
      return _QueueItem(
        key: ValueKey('$index-${track.id}'),
        track: track,
        index: index,
        selected: index == playback.currentIndex,
        playback: playback,
      );
    },
  );
}

class _QueueItem extends StatefulWidget {
  const _QueueItem({
    required this.track,
    required this.index,
    required this.selected,
    required this.playback,
    super.key,
  });

  final Track track;
  final int index;
  final bool selected;
  final PlaybackService playback;

  @override
  State<_QueueItem> createState() => _QueueItemState();
}

class _QueueItemState extends State<_QueueItem> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: ListTile(
      selected: widget.selected,
      selectedColor: SpotifinColors.accent,
      selectedTileColor: SpotifinColors.interactive,
      hoverColor: SpotifinColors.hover,
      onTap: () => widget.playback.playQueueIndex(widget.index),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ReorderableDragStartListener(
            index: widget.index,
            child: const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.drag_handle_rounded),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(SpotifinRadii.small),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Artwork(
                  itemId: widget.track.albumId ?? widget.track.id,
                  size: 44,
                  borderRadius: 0,
                ),
                AnimatedOpacity(
                  opacity: _hovered ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: const ColoredBox(
                    color: Color(0x99000000),
                    child: SizedBox.square(
                      dimension: 44,
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      title: Text(
        widget.track.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        widget.track.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        tooltip: 'Remove from queue',
        onPressed: () => widget.playback.removeAt(widget.index),
        icon: const Icon(Icons.close_rounded),
      ),
    ),
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
  final ScrollController _scrollController = ScrollController();
  List<GlobalKey> _lineKeys = const [];
  var _activeIndex = -1;
  var _followingLyrics = true;

  @override
  void initState() {
    super.initState();
    _lyrics = _load();
  }

  @override
  void didUpdateWidget(covariant _LyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id != widget.track.id) {
      _lyrics = _load();
      _lineKeys = const [];
      _activeIndex = -1;
      _followingLyrics = true;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
      if (snapshot.hasError) {
        return SpotifinEmptyState(
          icon: Icons.sync_problem_rounded,
          title: 'Could not load lyrics',
          message: snapshot.error.toString(),
        );
      }
      final lines = snapshot.data ?? const [];
      if (lines.isEmpty) {
        return const SpotifinEmptyState(
          icon: Icons.lyrics_outlined,
          title: 'No lyrics found',
        );
      }
      if (_lineKeys.length != lines.length) {
        _lineKeys = List.generate(lines.length, (_) => GlobalKey());
      }
      return StreamBuilder<Duration>(
        stream: widget.playback.player.positionStream,
        builder: (context, positionSnapshot) {
          final active = _activeLine(
            lines,
            positionSnapshot.data ?? Duration.zero,
          );
          _followActiveLine(active, lines.length);
          return NotificationListener<UserScrollNotification>(
            onNotification: (notification) {
              if (notification.direction != ScrollDirection.idle) {
                _followingLyrics = false;
              }
              return false;
            },
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 112),
              itemCount: lines.length,
              itemBuilder: (context, index) {
                final line = lines[index];
                return InkWell(
                  key: _lineKeys[index],
                  onTap: line.start == null
                      ? null
                      : () {
                          _followingLyrics = true;
                          _activeIndex = -1;
                          widget.playback.seek(line.start!);
                        },
                  borderRadius: BorderRadius.circular(SpotifinRadii.small),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      line.text,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: index == active
                            ? SpotifinColors.text
                            : SpotifinColors.textMuted,
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      );
    },
  );

  void _followActiveLine(int index, int lineCount) {
    if (index < 0 || index == _activeIndex) return;
    _activeIndex = index;
    if (!_followingLyrics) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || index != _activeIndex) return;
      final lineContext = _lineKeys[index].currentContext;
      if (lineContext != null) {
        _centerLine(lineContext);
        return;
      }
      if (!_scrollController.hasClients || lineCount < 2) return;
      final approximateOffset =
          _scrollController.position.maxScrollExtent * index / (lineCount - 1);
      _scrollController
          .animateTo(
            approximateOffset,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          )
          .then((_) {
            if (!mounted || index != _activeIndex) return;
            final context = _lineKeys[index].currentContext;
            if (context != null && context.mounted) _centerLine(context);
          });
    });
  }

  void _centerLine(BuildContext lineContext) {
    Scrollable.ensureVisible(
      lineContext,
      alignment: 0.5,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }
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
