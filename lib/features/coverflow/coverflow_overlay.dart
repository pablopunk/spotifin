import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../services/playback/playback_service.dart';
import '../../storage/database.dart';
import '../common/artwork.dart';
import '../common/design_system.dart';
import 'coverflow_controller.dart';
import 'coverflow_model.dart';
import 'coverflow_stage.dart';

class CoverflowOverlay extends ConsumerWidget {
  const CoverflowOverlay({required this.onDismiss, this.collection, super.key});

  final VoidCallback onDismiss;
  final MobileCoverflowCollection? collection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackProvider);
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) {
        if (collection case final collection?) {
          final initialIndex = collection.viewId == null
              ? collection.initialIndex
              : ref.watch(coverflowPositionProvider(collection.viewId!));
          return _OverlayShell(
            onDismiss: onDismiss,
            items: collection.items,
            initialIndex: initialIndex,
            playing: playback.playing,
            currentTrackId: playback.currentTrack?.id,
            onToggle: playback.toggle,
            onSelect: (index) =>
                _playCollectionItem(playback, collection, index),
            onTrackTap: (item, track) => playback.playTrack(track, item.tracks),
          );
        }
        final queue = playback.queue;
        if (queue.isNotEmpty) {
          return _OverlayShell(
            onDismiss: onDismiss,
            items: trackCoverflowItems(queue),
            initialIndex: _safeIndex(playback.currentIndex, queue.length),
            playing: playback.playing,
            currentTrackId: playback.currentTrack?.id,
            onToggle: playback.toggle,
            onSelect: playback.playQueueIndex,
            onTrackTap: (item, track) => playback.playTrack(track, item.tracks),
          );
        }
        return StreamBuilder<List<Track>>(
          stream: ref.watch(tracksByDateAddedStreamProvider),
          builder: (context, snapshot) {
            final fallback = snapshot.data ?? const <Track>[];
            if (fallback.isEmpty) return const SizedBox.shrink();
            return _OverlayShell(
              onDismiss: onDismiss,
              items: trackCoverflowItems(fallback),
              initialIndex: 0,
              onSelect: (index) =>
                  playback.replaceQueue(fallback, startIndex: index),
              onTrackTap: (item, track) =>
                  playback.playTrack(track, item.tracks),
            );
          },
        );
      },
    );
  }

  int _safeIndex(int? index, int length) {
    if (length == 0) return 0;
    return (index ?? 0).clamp(0, length - 1);
  }

  void _playCollectionItem(
    PlaybackService playback,
    MobileCoverflowCollection collection,
    int index,
  ) {
    final item = collection.items[index];
    if (item.tracks.isEmpty) return;
    if (collection.playback == MobileCoverflowPlayback.tracks) {
      playback.playTrack(item.tracks.single, collection.contextTracks);
      return;
    }
    playback.replaceQueue(item.tracks, shuffle: false);
  }
}

class _OverlayShell extends StatefulWidget {
  const _OverlayShell({
    required this.onDismiss,
    required this.items,
    required this.onSelect,
    required this.onTrackTap,
    this.initialIndex = 0,
    this.playing = false,
    this.currentTrackId,
    this.onToggle,
  });

  final VoidCallback onDismiss;
  final List<CoverflowItem> items;
  final ValueChanged<int> onSelect;
  final CoverflowTrackTap onTrackTap;
  final int initialIndex;
  final bool playing;
  final String? currentTrackId;
  final VoidCallback? onToggle;

  @override
  State<_OverlayShell> createState() => _OverlayShellState();
}

class _OverlayShellState extends State<_OverlayShell> {
  late int _focused;

  @override
  void initState() {
    super.initState();
    _focused = _safeIndex(widget.initialIndex);
  }

  @override
  void didUpdateWidget(covariant _OverlayShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialIndex != oldWidget.initialIndex) {
      _focused = _safeIndex(widget.initialIndex);
    } else if (widget.items != oldWidget.items) {
      _focused = _safeIndex(_focused);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height: constraints.maxHeight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragEnd: (details) {
                      if ((details.primaryVelocity ?? 0) > 320) {
                        widget.onDismiss();
                      }
                    },
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CoverflowStage(
                            items: widget.items,
                            initialIndex: _focused,
                            showCaption: false,
                            showReflection: false,
                            fillHeight: true,
                            currentTrackId: widget.currentTrackId,
                            playing: widget.playing,
                            onFocus: _focus,
                            onCenterTap: (item) => _activate(_indexOf(item)),
                            onTrackTap: widget.onTrackTap,
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 8,
                          child: IconButton(
                            tooltip: 'Dismiss',
                            onPressed: widget.onDismiss,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
                            color: SpotifinColors.textMuted,
                          ),
                        ),
                        Positioned(
                          left: 88,
                          right: 88,
                          bottom: 0,
                          child: _TrackLine(item: widget.items[_focused]),
                        ),
                        Positioned(
                          right: 14,
                          bottom: 10,
                          child: Opacity(
                            opacity: 0.78,
                            child: SpotifinPlayButton(
                              onPressed:
                                  widget.onToggle ??
                                  () => widget.onSelect(_focused),
                              playing: widget.playing,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: Divider(height: 1)),
              SliverList.builder(
                itemCount: widget.items.length,
                itemBuilder: (context, index) => _QueueRow(
                  item: widget.items[index],
                  selected: index == _focused,
                  onTap: () => widget.onSelect(index),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }

  int _indexOf(CoverflowItem item) {
    final index = widget.items.indexWhere((entry) => entry.id == item.id);
    return index < 0 ? 0 : index;
  }

  void _focus(int index) {
    final selected = _safeIndex(index);
    if (selected != _focused) setState(() => _focused = selected);
  }

  void _activate(int index) {
    final selected = _safeIndex(index);
    final isCurrent = widget.items[selected].tracks.any(
      (track) => track.id == widget.currentTrackId,
    );
    if (isCurrent) {
      widget.onToggle?.call();
    } else {
      widget.onSelect(selected);
    }
  }

  int _safeIndex(int index) {
    if (widget.items.isEmpty) return 0;
    return index.clamp(0, widget.items.length - 1);
  }
}

class _TrackLine extends StatelessWidget {
  const _TrackLine({required this.item});

  final CoverflowItem item;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(text: '${item.title}  '),
        TextSpan(
          text: item.subtitle,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: TextAlign.center,
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Colors.white.withValues(alpha: 0.82),
      shadows: const [Shadow(color: Colors.black, blurRadius: 8)],
    ),
  );
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final CoverflowItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    selected: selected,
    selectedColor: SpotifinColors.accent,
    leading: Artwork(
      itemId: item.artItemId,
      size: 44,
      borderRadius: SpotifinRadii.small,
    ),
    title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
    onTap: onTap,
  );
}
