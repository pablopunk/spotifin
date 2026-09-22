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
import 'player_collection_links.dart';
import 'remote_devices.dart';

class PlayerSidePanel extends ConsumerWidget {
  const PlayerSidePanel({super.key});

  static const _narrowWidth = 560.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackProvider);
    final panels = ref.watch(playerPanelProvider);
    final panelController = ref.read(playerPanelProvider.notifier);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxOpen = constraints.maxWidth < _narrowWidth ? 2 : 4;
        if (panels.openPanels.length > maxOpen) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => panelController.constrainTo(maxOpen),
          );
        }
        return Material(
          color: SpotifinColors.background,
          child: Column(
            children: [
              _PanelHeader(
                panels: panels,
                maxOpen: maxOpen,
                compact: constraints.maxWidth < 480,
              ),
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
                    return _ResponsivePanelSections(
                      panels: panels,
                      controller: panelController,
                      track: track,
                      playback: playback,
                      useQuadrants: maxOpen == 4,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ResponsivePanelSections extends StatelessWidget {
  const _ResponsivePanelSections({
    required this.panels,
    required this.controller,
    required this.track,
    required this.playback,
    required this.useQuadrants,
  });

  final PlayerPanelState panels;
  final PlayerPanelController controller;
  final Track track;
  final PlaybackService playback;
  final bool useQuadrants;

  @override
  Widget build(BuildContext context) {
    final sections = _activeSections(panels.displayPanels);
    return useQuadrants
        ? _QuadrantPanelSections(sections: sections)
        : _VerticalPanelSections(sections: sections);
  }

  List<Widget> _activeSections(Iterable<PlayerPanel> candidates) => candidates
      .where(panels.openPanels.contains)
      .map(_section)
      .toList(growable: false);

  Widget _section(PlayerPanel panel) => switch (panel) {
    PlayerPanel.player => _PanelSection(
      title: 'Now playing',
      onClose: controller.togglePlayer,
      child: _PlayerPanel(track: track, playback: playback),
    ),
    PlayerPanel.lyrics => _PanelSection(
      title: 'Lyrics',
      onClose: controller.toggleLyrics,
      child: _LyricsPanel(track: track, playback: playback),
    ),
    PlayerPanel.queue => _PanelSection(
      title: 'Queue',
      onClose: controller.toggleQueue,
      child: _QueuePanel(playback: playback),
    ),
    PlayerPanel.history => _PanelSection(
      title: 'History',
      onClose: controller.toggleHistory,
      child: _HistoryPanel(playback: playback),
    ),
  };
}

class _VerticalPanelSections extends StatelessWidget {
  const _VerticalPanelSections({required this.sections});

  final List<Widget> sections;

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) return const SizedBox.shrink();
    if (sections.length < 2) {
      return _PanelCard(child: sections.single);
    }
    return Column(
      children: [
        Expanded(child: _PanelCard(child: sections.first)),
        const SizedBox(height: SpotifinSpacing.xs),
        Expanded(child: _PanelCard(child: sections.last)),
      ],
    );
  }
}

class _QuadrantPanelSections extends StatelessWidget {
  const _QuadrantPanelSections({required this.sections});

  final List<Widget> sections;

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) return const SizedBox.shrink();
    if (sections.length == 1) return _PanelCard(child: sections.single);
    if (sections.length == 2) return _QuadrantRow(sections: sections);
    final top = sections.take(2).toList(growable: false);
    final bottom = sections.skip(2).toList(growable: false);
    return Column(
      children: [
        Expanded(child: _QuadrantRow(sections: top)),
        const SizedBox(height: SpotifinSpacing.xs),
        Expanded(child: _QuadrantRow(sections: bottom)),
      ],
    );
  }
}

class _QuadrantRow extends StatelessWidget {
  const _QuadrantRow({required this.sections});

  final List<Widget> sections;

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) return const SizedBox.shrink();
    if (sections.length < 2) {
      return _PanelCard(child: sections.single);
    }
    return Row(
      children: [
        Expanded(child: _PanelCard(child: sections.first)),
        const SizedBox(width: SpotifinSpacing.xs),
        Expanded(child: _PanelCard(child: sections.last)),
      ],
    );
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(SpotifinRadii.card),
    child: ColoredBox(color: SpotifinColors.surface, child: child),
  );
}

class _PanelHeader extends ConsumerWidget {
  const _PanelHeader({
    required this.panels,
    required this.maxOpen,
    required this.compact,
  });

  final PlayerPanelState panels;
  final int maxOpen;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
    child: Row(
      children: [
        _PanelTab(
          label: 'Player',
          icon: Icons.album_rounded,
          selected: panels.player,
          compact: compact,
          onPressed: () => ref
              .read(playerPanelProvider.notifier)
              .togglePlayer(maxOpen: maxOpen),
        ),
        _PanelTab(
          label: 'Lyrics',
          icon: Icons.lyrics_outlined,
          selected: panels.lyrics,
          compact: compact,
          onPressed: () => ref
              .read(playerPanelProvider.notifier)
              .toggleLyrics(maxOpen: maxOpen),
        ),
        _PanelTab(
          label: 'Queue',
          icon: Icons.queue_music_rounded,
          selected: panels.queue,
          compact: compact,
          onPressed: () => ref
              .read(playerPanelProvider.notifier)
              .toggleQueue(maxOpen: maxOpen),
        ),
        _PanelTab(
          label: 'History',
          icon: Icons.history_rounded,
          selected: panels.history,
          compact: compact,
          onPressed: () => ref
              .read(playerPanelProvider.notifier)
              .toggleHistory(maxOpen: maxOpen),
        ),
        const Spacer(),
        const RemoteDeviceButton(),
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
    required this.compact,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = selected ? SpotifinColors.accent : SpotifinColors.textMuted;
    if (compact) {
      return IconButton(
        tooltip: label,
        onPressed: onPressed,
        color: color,
        icon: Icon(icon, size: 19),
        visualDensity: VisualDensity.compact,
      );
    }
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 36),
        visualDensity: VisualDensity.compact,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
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
          child: PlayerCollectionLinks(
            track: track,
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

class _HistoryPanel extends StatelessWidget {
  const _HistoryPanel({required this.playback});

  final PlaybackService playback;

  @override
  Widget build(BuildContext context) {
    final history = playback.history;
    if (history.isEmpty) {
      return const SpotifinEmptyState(
        icon: Icons.history_rounded,
        title: 'No history yet',
        message: 'Tracks you finish will show up here.',
      );
    }
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: playback.clearHistory,
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              label: const Text('Clear'),
              style: TextButton.styleFrom(
                foregroundColor: SpotifinColors.textMuted,
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 112),
            itemCount: history.length,
            itemBuilder: (context, index) => _HistoryItem(
              key: ValueKey('$index-${history[index].id}'),
              track: history[index],
              index: index,
              playback: playback,
            ),
          ),
        ),
      ],
    );
  }
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

class _HistoryItem extends StatefulWidget {
  const _HistoryItem({
    required this.track,
    required this.index,
    required this.playback,
    super.key,
  });

  final Track track;
  final int index;
  final PlaybackService playback;

  @override
  State<_HistoryItem> createState() => _HistoryItemState();
}

class _HistoryItemState extends State<_HistoryItem> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: ListTile(
      hoverColor: SpotifinColors.hover,
      onTap: () => widget.playback.playHistoryIndex(widget.index),
      leading: ClipRRect(
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
                  child: Icon(Icons.play_arrow_rounded, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
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
      trailing: const Icon(
        Icons.history_rounded,
        size: 18,
        color: SpotifinColors.textMuted,
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
