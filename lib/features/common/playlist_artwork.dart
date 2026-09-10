import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../storage/database.dart';
import 'artwork.dart';

class PlaylistArtwork extends StatelessWidget {
  const PlaylistArtwork({
    required this.tracks,
    required this.size,
    this.borderRadius = SpotifinRadii.small,
    super.key,
  });

  final List<Track> tracks;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final artworkIds = _firstAlbumArtworkIds(tracks);
    if (artworkIds.isEmpty) return _fallback();
    if (artworkIds.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Artwork(itemId: artworkIds.single, size: size, borderRadius: 0),
      );
    }
    final tileSize = size / 2;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox.square(
        dimension: size,
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
          ),
          itemCount: 4,
          itemBuilder: (context, index) => index < artworkIds.length
              ? Artwork(
                  itemId: artworkIds[index],
                  size: tileSize,
                  borderRadius: 0,
                )
              : _emptyTile(tileSize),
        ),
      ),
    );
  }

  Widget _fallback() => ClipRRect(
    borderRadius: BorderRadius.circular(borderRadius),
    child: _emptyTile(size),
  );

  Widget _emptyTile(double tileSize) => Container(
    width: tileSize,
    height: tileSize,
    color: SpotifinColors.raised,
    alignment: Alignment.center,
    child: Icon(
      Icons.queue_music_rounded,
      size: tileSize * .46,
      color: SpotifinColors.textMuted,
    ),
  );
}

List<Track> tracksInPlaylist(Playlist playlist, Map<String, Track> tracksById) {
  try {
    return (jsonDecode(playlist.trackIds) as List<dynamic>)
        .cast<String>()
        .map((id) => tracksById[id])
        .whereType<Track>()
        .toList();
  } on Object {
    return const [];
  }
}

List<String> _firstAlbumArtworkIds(List<Track> tracks) {
  final seenAlbums = <String>{};
  final artworkIds = <String>[];
  for (final track in tracks) {
    final albumKey = track.albumId ?? '${track.artist}\u0000${track.album}';
    if (!seenAlbums.add(albumKey)) continue;
    artworkIds.add(track.albumId ?? track.id);
    if (artworkIds.length == 4) break;
  }
  return artworkIds;
}
