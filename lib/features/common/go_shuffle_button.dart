import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../storage/database.dart';
import 'design_system.dart';

class GoShuffleButton extends ConsumerWidget {
  const GoShuffleButton({required this.tracks, super.key});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: SpotifinColors.accent,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: SpotifinSpacing.sm),
      ),
      onPressed: tracks.isEmpty
          ? null
          : () => ref
                .read(activePlaybackProvider)
                .replaceQueue(tracks, shuffle: true),
      icon: const Icon(Icons.shuffle_rounded),
      label: const Text(
        'Go shuffle',
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
