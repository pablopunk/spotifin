import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../storage/database.dart';
import 'artwork.dart';

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
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
    leading: Artwork(itemId: track.id),
    title: Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      [
        track.artist,
        if (showAlbum && track.album.isNotEmpty) track.album,
      ].join(' • '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    onTap: () => ref.read(playbackProvider).playTrack(track, contextTracks),
    trailing: PopupMenuButton<String>(
      tooltip: 'More options',
      onSelected: (action) async {
        if (action == 'favorite') {
          await ref
              .read(appControllerProvider.notifier)
              .toggleFavorite(track.id, !track.favorite);
        } else if (action == 'queue') {
          await ref.read(playbackProvider).addToQueue(track);
        } else if (action == 'download') {
          final session = ref.read(appControllerProvider).session;
          if (session != null) {
            await ref
                .read(downloadProvider)
                .download(
                  session,
                  track,
                  small: ref.read(appControllerProvider).smallDownloads,
                );
          }
        } else if (action == 'playlist') {
          await _addToPlaylist(context, ref);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'favorite',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              track.favorite ? Icons.favorite : Icons.favorite_border,
            ),
            title: Text(track.favorite ? 'Remove favorite' : 'Favorite'),
          ),
        ),
        const PopupMenuItem(
          value: 'playlist',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.library_add_rounded),
            title: Text('Add to playlist'),
          ),
        ),
        const PopupMenuItem(
          value: 'queue',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.playlist_add_rounded),
            title: Text('Add to queue'),
          ),
        ),
        const PopupMenuItem(
          value: 'download',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.download_rounded),
            title: Text('Download'),
          ),
        ),
      ],
    ),
  );

  Future<void> _addToPlaylist(BuildContext context, WidgetRef ref) async {
    final playlists = await ref
        .read(databaseProvider)
        .select(ref.read(databaseProvider).playlists)
        .get();
    if (!context.mounted) return;
    if (playlists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Create a playlist from the current queue first.'),
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
}
