import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../storage/database.dart';
import 'artwork.dart';
import 'context_menu.dart';
import 'design_system.dart';

class TrackTile extends ConsumerWidget {
  const TrackTile({
    required this.track,
    required this.contextTracks,
    this.showAlbum = true,
    super.key,
  });

  final Track track;
  final List<Track> contextTracks;
  final bool showAlbum;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tile = Padding(
      padding: const EdgeInsets.symmetric(horizontal: SpotifinSpacing.sm),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(SpotifinRadii.small),
        child: Row(
          children: [
            Expanded(
              child: ListTile(
                minTileHeight: 64,
                contentPadding: const EdgeInsets.only(left: SpotifinSpacing.xs),
                leading: Artwork(
                  itemId: track.albumId ?? track.id,
                  size: 48,
                  borderRadius: SpotifinRadii.small,
                ),
                title: Text(
                  track.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                subtitle: Text(
                  [
                    track.artist,
                    if (showAlbum && track.album.isNotEmpty) track.album,
                  ].join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                onTap: () =>
                    ref.read(playbackProvider).playTrack(track, contextTracks),
              ),
            ),
            TrackMenuButton(track: track, contextTracks: contextTracks),
          ],
        ),
      ),
    );
    return TrackContextMenu(
      track: track,
      contextTracks: contextTracks,
      child: DraggableTrack(track: track, child: tile),
    );
  }
}

enum _TrackAction { favorite, playlist, queue, download, delete }

class TrackContextMenu extends ConsumerWidget {
  const TrackContextMenu({
    required this.track,
    required this.contextTracks,
    required this.child,
    super.key,
  });

  final Track track;
  final List<Track> contextTracks;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onSecondaryTapDown: (details) => _showTrackMenu(
      context,
      ref,
      track,
      contextTracks,
      details.globalPosition,
    ),
    child: child,
  );
}

class TrackMenuButton extends ConsumerWidget {
  const TrackMenuButton({
    required this.track,
    required this.contextTracks,
    super.key,
  });

  final Track track;
  final List<Track> contextTracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      PopupMenuButton<_TrackAction>(
        color: SpotifinColors.raised,
        constraints: spotifinMenuConstraints,
        tooltip: 'More options',
        onSelected: (action) =>
            _handleTrackAction(context, ref, track, contextTracks, action),
        itemBuilder: (_) => _trackMenuItems(track),
      );
}

List<PopupMenuEntry<_TrackAction>> _trackMenuItems(Track track) => [
  PopupMenuItem(
    height: 40,
    value: _TrackAction.favorite,
    child: SpotifinMenuLabel(
      icon: track.favorite ? Icons.favorite : Icons.favorite_border,
      label: track.favorite ? 'Remove favorite' : 'Favorite',
    ),
  ),
  const PopupMenuItem(
    height: 40,
    value: _TrackAction.playlist,
    child: SpotifinMenuLabel(
      icon: Icons.library_add_rounded,
      label: 'Add to playlist',
    ),
  ),
  const PopupMenuItem(
    height: 40,
    value: _TrackAction.queue,
    child: SpotifinMenuLabel(
      icon: Icons.playlist_add_rounded,
      label: 'Add to queue',
    ),
  ),
  const PopupMenuItem(
    height: 40,
    value: _TrackAction.download,
    child: SpotifinMenuLabel(icon: Icons.download_rounded, label: 'Download'),
  ),
  const PopupMenuDivider(height: 9),
  const PopupMenuItem(
    height: 40,
    value: _TrackAction.delete,
    child: SpotifinMenuLabel(
      icon: Icons.delete_forever_rounded,
      label: 'Delete permanently',
      destructive: true,
    ),
  ),
];

Future<void> _showTrackMenu(
  BuildContext context,
  WidgetRef ref,
  Track track,
  List<Track> contextTracks,
  Offset globalPosition,
) async {
  final action = await showMenu<_TrackAction>(
    context: context,
    color: SpotifinColors.raised,
    constraints: spotifinMenuConstraints,
    position: spotifinMenuPosition(context, globalPosition),
    items: _trackMenuItems(track),
  );
  if (action != null && context.mounted) {
    await _handleTrackAction(context, ref, track, contextTracks, action);
  }
}

Future<void> _handleTrackAction(
  BuildContext context,
  WidgetRef ref,
  Track track,
  List<Track> contextTracks,
  _TrackAction action,
) async {
  if (action == _TrackAction.favorite) {
    await ref
        .read(appControllerProvider.notifier)
        .toggleFavorite(track.id, !track.favorite);
  } else if (action == _TrackAction.queue) {
    await ref.read(playbackProvider).addToQueue(track);
  } else if (action == _TrackAction.download) {
    final app = ref.read(appControllerProvider);
    if (app.session != null) {
      await ref
          .read(downloadProvider)
          .download(app.session!, track, small: app.smallDownloads);
    }
  } else if (action == _TrackAction.playlist) {
    await _addToPlaylist(context, ref, track);
  } else if (action == _TrackAction.delete) {
    await _deleteTrack(context, ref, track);
  }
}

Future<void> _addToPlaylist(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final playlists = await ref
      .read(databaseProvider)
      .select(ref.read(databaseProvider).playlists)
      .get();
  if (!context.mounted) return;
  if (playlists.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Create a playlist from the sidebar first.'),
      ),
    );
    return;
  }
  final selected = await showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Add to playlist'),
      children: playlists
          .map(
            (playlist) => SimpleDialogOption(
              onPressed: () => Navigator.pop(context, playlist.id),
              child: Text(playlist.name),
            ),
          )
          .toList(),
    ),
  );
  if (selected != null) {
    await ref
        .read(appControllerProvider.notifier)
        .addToPlaylist(selected, track.id);
  }
}

Future<void> _deleteTrack(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete song permanently?'),
      content: Text(
        '“${track.name}” will be deleted from Jellyfin and its storage. '
        'This cannot be undone.',
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
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await ref.read(appControllerProvider.notifier).deleteTrack(track.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Deleted “${track.name}”.')));
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not delete “${track.name}”: $error')),
    );
  }
}

class DraggableTrack extends StatelessWidget {
  const DraggableTrack({required this.track, required this.child, super.key});

  final Track track;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < SpotifinBreakpoints.extendedRail) {
      return child;
    }
    return Draggable<Track>(
      data: track,
      feedback: Material(
        color: SpotifinColors.raised,
        elevation: 8,
        borderRadius: BorderRadius.circular(SpotifinRadii.small),
        child: SizedBox(
          width: 240,
          child: ListTile(
            leading: const Icon(Icons.music_note_rounded),
            title: Text(track.name, maxLines: 1),
            subtitle: Text(track.artist, maxLines: 1),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.45, child: child),
      child: child,
    );
  }
}
