import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../storage/database.dart';
import 'context_menu.dart';
import 'playlist_actions.dart';

class PlaylistContextMenu extends ConsumerWidget {
  const PlaylistContextMenu({
    required this.playlist,
    required this.tracks,
    required this.child,
    super.key,
  });

  final Playlist playlist;
  final List<Track> tracks;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onSecondaryTapDown: (details) =>
        _showMenu(context, ref, details.globalPosition),
    child: child,
  );

  List<PopupMenuEntry<_PlaylistAction>> _items() => const [
    PopupMenuItem(
      height: 40,
      value: _PlaylistAction.play,
      child: SpotifinMenuLabel(icon: Icons.play_arrow_rounded, label: 'Play'),
    ),
    PopupMenuItem(
      height: 40,
      value: _PlaylistAction.queue,
      child: SpotifinMenuLabel(
        icon: Icons.playlist_add_rounded,
        label: 'Add to queue',
      ),
    ),
    PopupMenuItem(
      height: 40,
      value: _PlaylistAction.download,
      child: SpotifinMenuLabel(icon: Icons.download_rounded, label: 'Download'),
    ),
    PopupMenuDivider(height: 9),
    PopupMenuItem(
      height: 40,
      value: _PlaylistAction.rename,
      child: SpotifinMenuLabel(
        icon: Icons.edit_rounded,
        label: 'Rename playlist',
      ),
    ),
    PopupMenuItem(
      height: 40,
      value: _PlaylistAction.remove,
      child: SpotifinMenuLabel(
        icon: Icons.delete_outline_rounded,
        label: 'Remove playlist',
        destructive: true,
      ),
    ),
  ];

  Future<void> _showMenu(
    BuildContext context,
    WidgetRef ref,
    Offset globalPosition,
  ) async {
    final action = await showMenu<_PlaylistAction>(
      context: context,
      color: SpotifinColors.raised,
      constraints: spotifinMenuConstraints,
      position: spotifinMenuPosition(context, globalPosition),
      items: _items(),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _PlaylistAction.play:
        await ref.read(playbackProvider).replaceQueue(tracks);
      case _PlaylistAction.queue:
        for (final track in tracks) {
          await ref.read(playbackProvider).addToQueue(track);
        }
      case _PlaylistAction.download:
        await _download(ref);
      case _PlaylistAction.rename:
        await renamePlaylist(context, ref, playlist);
      case _PlaylistAction.remove:
        await removePlaylist(context, ref, playlist);
    }
  }

  Future<void> _download(WidgetRef ref) async {
    final app = ref.read(appControllerProvider);
    if (app.session == null) return;
    await ref
        .read(downloadProvider)
        .downloadAll(app.session!, tracks, small: app.smallDownloads);
  }
}

enum _PlaylistAction { play, queue, download, rename, remove }
