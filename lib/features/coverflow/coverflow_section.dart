import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'coverflow_controller.dart';
import 'coverflow_model.dart';
import 'coverflow_stage.dart';
import '../../app/providers.dart';

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
    if (!coverflow) return list;
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          SizedBox(
            height: (constraints.maxHeight * 0.62).clamp(360.0, 560.0),
            child: CoverflowStage(
              items: items,
              onCenterTap: (item) {
                final playback = ref.read(playbackProvider);
                if (playback.currentTrack?.id == item.tracks.single.id) {
                  playback.toggle();
                } else {
                  onCenterTap(item);
                }
              },
              onTrackTap: (item, track) =>
                  ref.read(playbackProvider).playTrack(track, item.tracks),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: list),
        ],
      ),
    );
  }
}
