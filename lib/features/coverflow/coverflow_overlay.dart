import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../storage/database.dart';
import '../common/artwork.dart';
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
            currentId: playback.currentTrack?.id,
            playing: playback.playing,
            showTransport: true,
            onPrevious: playback.previous,
            onToggle: playback.toggle,
            onNext: playback.next,
            onSelect: (index) => playback.playQueueIndex(index),
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
              showTransport: false,
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

class _OverlayShell extends StatelessWidget {
  const _OverlayShell({
    required this.onDismiss,
    required this.items,
    required this.onSelect,
    this.initialIndex = 0,
    this.currentId,
    this.playing = false,
    this.showTransport = false,
    this.onPrevious,
    this.onToggle,
    this.onNext,
  });

  final VoidCallback onDismiss;
  final List<CoverflowItem> items;
  final ValueChanged<int> onSelect;
  final int initialIndex;
  final String? currentId;
  final bool playing;
  final bool showTransport;
  final VoidCallback? onPrevious;
  final VoidCallback? onToggle;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(
                  height: constraints.maxHeight,
                  child: Column(
                    children: [
                      _TopBar(onDismiss: onDismiss),
                      Expanded(
                        child: CoverflowStage(
                          items: items,
                          initialIndex: initialIndex,
                          onCenterTap: (item) => onSelect(_indexOf(item)),
                        ),
                      ),
                      if (showTransport)
                        _Transport(
                          playing: playing,
                          onPrevious: onPrevious,
                          onToggle: onToggle,
                          onNext: onNext,
                        )
                      else
                        const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: Divider(height: 1)),
              SliverList.builder(
                itemCount: items.length,
                itemBuilder: (context, index) => _QueueRow(
                  item: items[index],
                  selected: index == initialIndex,
                  onTap: () => onSelect(index),
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
    final index = items.indexWhere((entry) => entry.id == item.id);
    return index < 0 ? 0 : index;
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onVerticalDragEnd: (details) {
      if ((details.primaryVelocity ?? 0) > 320) onDismiss();
    },
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          const SizedBox(width: 40),
          Expanded(
            child: Text(
              'Cover Flow',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: SpotifinColors.textMuted),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: onDismiss,
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
            color: SpotifinColors.textMuted,
          ),
        ],
      ),
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

class _Transport extends StatelessWidget {
  const _Transport({
    required this.playing,
    this.onPrevious,
    this.onToggle,
    this.onNext,
  });

  final bool playing;
  final VoidCallback? onPrevious;
  final VoidCallback? onToggle;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Previous',
          onPressed: onPrevious,
          icon: const Icon(Icons.skip_previous_rounded, size: 32),
          color: SpotifinColors.text,
        ),
        const SizedBox(width: 24),
        IconButton(
          tooltip: playing ? 'Pause' : 'Play',
          onPressed: onToggle,
          icon: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 40,
          ),
          color: SpotifinColors.text,
        ),
        const SizedBox(width: 24),
        IconButton(
          tooltip: 'Next',
          onPressed: onNext,
          icon: const Icon(Icons.skip_next_rounded, size: 32),
          color: SpotifinColors.text,
        ),
      ],
    ),
  );
}
