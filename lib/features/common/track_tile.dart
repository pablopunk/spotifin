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
          value: 'queue',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.playlist_add_rounded),
            title: Text('Add to queue'),
          ),
        ),
      ],
    ),
  );
}
