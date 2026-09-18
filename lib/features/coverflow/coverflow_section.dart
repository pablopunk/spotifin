import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'coverflow_controller.dart';
import 'coverflow_model.dart';
import 'coverflow_stage.dart';

class CoverflowSection extends ConsumerWidget {
  const CoverflowSection({
    required this.viewId,
    required this.items,
    required this.list,
    required this.onCenterTap,
    super.key,
  });

  final String viewId;
  final List<CoverflowItem> items;
  final Widget list;
  final ValueChanged<CoverflowItem> onCenterTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coverflow = ref.watch(coverflowModeProvider(viewId));
    final trackedList = CoverflowScrollTracker(
      viewId: viewId,
      itemCount: items.length,
      child: list,
    );
    if (!coverflow) return trackedList;
    final initialIndex = ref.watch(coverflowPositionProvider(viewId));
    final playback = ref.watch(playbackProvider);
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          SizedBox(
            height: (constraints.maxHeight * 0.62).clamp(360.0, 560.0),
            child: ListenableBuilder(
              listenable: playback,
              builder: (context, _) => CoverflowStage(
                items: items,
                initialIndex: initialIndex,
                currentTrackId: playback.currentTrack?.id,
                playing: playback.playing,
                onFocus: (index) => ref
                    .read(coverflowPositionProvider(viewId).notifier)
                    .set(index),
                onCenterTap: (item) {
                  if (playback.currentTrack?.id == item.tracks.single.id) {
                    playback.toggle();
                  } else {
                    onCenterTap(item);
                  }
                },
                onTrackTap: (item, track) =>
                    playback.playTrack(track, item.tracks),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: list),
        ],
      ),
    );
  }
}

class CoverflowScrollTracker extends ConsumerWidget {
  const CoverflowScrollTracker({
    required this.viewId,
    required this.itemCount,
    required this.child,
    super.key,
  });

  final String viewId;
  final int itemCount;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.depth != 0 || itemCount == 0) return false;
          final metrics = notification.metrics;
          final contentExtent =
              metrics.maxScrollExtent + metrics.viewportDimension;
          if (contentExtent <= 0) return false;
          final center =
              metrics.pixels.clamp(0.0, metrics.maxScrollExtent) +
              metrics.viewportDimension / 2;
          final index = (center / contentExtent * itemCount).floor().clamp(
            0,
            itemCount - 1,
          );
          ref.read(coverflowPositionProvider(viewId).notifier).set(index);
          return false;
        },
        child: child,
      );
}
