import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../storage/database.dart';
import '../common/artwork.dart';
import '../common/design_system.dart';
import 'coverflow_model.dart';
import 'coverflow_stage.dart';

class CoverflowOverlay extends ConsumerWidget {
  const CoverflowOverlay({required this.onDismiss, super.key});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackProvider);
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) {
        final queue = playback.queue;
        if (queue.isNotEmpty) {
          return _OverlayShell(
            onDismiss: onDismiss,
            items: trackCoverflowItems(queue),
            initialIndex: _safeIndex(playback.currentIndex, queue.length),
            playing: playback.playing,
            hasPlayback: true,
            onToggle: playback.toggle,
            onSelect: playback.playQueueIndex,
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
}

class _OverlayShell extends StatefulWidget {
  const _OverlayShell({
    required this.onDismiss,
    required this.items,
    required this.onSelect,
    this.initialIndex = 0,
    this.playing = false,
    this.hasPlayback = false,
    this.onToggle,
  });

  final VoidCallback onDismiss;
  final List<CoverflowItem> items;
  final ValueChanged<int> onSelect;
  final int initialIndex;
  final bool playing;
  final bool hasPlayback;
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
                            onFocus: _select,
                            onCenterTap: (item) => _select(_indexOf(item)),
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
                          right: 16,
                          bottom: 16,
                          child: _NowPlayingPill(
                            item: widget.items[_focused],
                            playing: widget.playing,
                            onToggle: widget.hasPlayback
                                ? widget.onToggle
                                : () => widget.onSelect(_focused),
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
                  onTap: () => _select(index),
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

  void _select(int index) {
    final selected = _safeIndex(index);
    if (selected == _focused) return;
    setState(() => _focused = selected);
    widget.onSelect(selected);
  }

  int _safeIndex(int index) {
    if (widget.items.isEmpty) return 0;
    return index.clamp(0, widget.items.length - 1);
  }
}

class _NowPlayingPill extends StatelessWidget {
  const _NowPlayingPill({
    required this.item,
    required this.playing,
    required this.onToggle,
  });

  final CoverflowItem item;
  final bool playing;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 320),
    padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
    decoration: BoxDecoration(
      color: SpotifinColors.surface.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      boxShadow: const [
        BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 8)),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                item.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: SpotifinColors.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SpotifinPlayButton(onPressed: onToggle, playing: playing),
      ],
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
