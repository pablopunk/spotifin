import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../storage/database.dart';
import 'context_menu.dart';

class AlbumContextMenu extends ConsumerWidget {
  const AlbumContextMenu({
    required this.title,
    required this.tracks,
    required this.child,
    super.key,
  });

  final String title;
  final List<Track> tracks;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onSecondaryTapDown: (details) =>
        _showMenu(context, ref, details.globalPosition),
    child: child,
  );

  List<PopupMenuEntry<String>> _items() => const [
    PopupMenuItem(
      height: 40,
      value: 'play',
      child: SpotifinMenuLabel(icon: Icons.play_arrow_rounded, label: 'Play'),
    ),
    PopupMenuItem(
      height: 40,
      value: 'queue',
      child: SpotifinMenuLabel(
        icon: Icons.playlist_add_rounded,
        label: 'Add to queue',
      ),
    ),
    PopupMenuItem(
      height: 40,
      value: 'download',
      child: SpotifinMenuLabel(icon: Icons.download_rounded, label: 'Download'),
    ),
    PopupMenuDivider(height: 9),
    PopupMenuItem(
      height: 40,
      value: 'delete',
      child: SpotifinMenuLabel(
        icon: Icons.delete_forever_rounded,
        label: 'Delete album permanently',
        destructive: true,
      ),
    ),
  ];

  Future<void> _showMenu(
    BuildContext context,
    WidgetRef ref,
    Offset globalPosition,
  ) async {
    final action = await showMenu<String>(
      context: context,
      color: SpotifinColors.raised,
      constraints: spotifinMenuConstraints,
      position: spotifinMenuPosition(context, globalPosition),
      items: _items(),
    );
    if (action == null || !context.mounted) return;
    if (action == 'play') {
      await ref.read(playbackProvider).replaceQueue(tracks);
    } else if (action == 'queue') {
      for (final track in tracks) {
        await ref.read(playbackProvider).addToQueue(track);
      }
    } else if (action == 'download') {
      await _download(ref);
    } else if (action == 'delete') {
      await _delete(context, ref);
    }
  }

  Future<void> _download(WidgetRef ref) async {
    final app = ref.read(appControllerProvider);
    if (app.session == null) return;
    for (final track in tracks) {
      await ref
          .read(downloadProvider)
          .download(app.session!, track, small: app.smallDownloads);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete album permanently?'),
        content: Text(
          '“$title” and all ${tracks.length} of its songs will be deleted '
          'from Jellyfin and its storage. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: SpotifinColors.negative,
              foregroundColor: SpotifinColors.voidBlack,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete album'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref
          .read(appControllerProvider.notifier)
          .deleteAlbum(tracks.map((track) => track.id));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Deleted “$title”.')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete “$title”: $error')),
      );
    }
  }
}
