import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';

class PlayerPanelTabs extends ConsumerWidget {
  const PlayerPanelTabs({this.includePlayer = true, super.key});

  final bool includePlayer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final panels = ref.watch(playerPanelProvider);
    final controller = ref.read(playerPanelProvider.notifier);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (includePlayer)
          _PanelTab(
            tooltip: 'Now playing',
            icon: Icons.album_rounded,
            selected: panels.player,
            onPressed: controller.togglePlayer,
          ),
        _PanelTab(
          tooltip: 'Lyrics',
          icon: Icons.lyrics_outlined,
          selected: panels.lyrics,
          onPressed: controller.toggleLyrics,
        ),
        _PanelTab(
          tooltip: 'Queue',
          icon: Icons.queue_music_rounded,
          selected: panels.queue,
          onPressed: controller.toggleQueue,
        ),
        _PanelTab(
          tooltip: 'History',
          icon: Icons.history_rounded,
          selected: panels.history,
          onPressed: controller.toggleHistory,
        ),
      ],
    );
  }
}

class _PanelTab extends StatelessWidget {
  const _PanelTab({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    isSelected: selected,
    onPressed: onPressed,
    visualDensity: VisualDensity.compact,
    color: selected ? SpotifinColors.accent : SpotifinColors.textMuted,
    style: IconButton.styleFrom(
      backgroundColor: selected
          ? SpotifinColors.accent.withValues(alpha: .16)
          : Colors.transparent,
    ),
    icon: Icon(icon, size: 19),
  );
}
