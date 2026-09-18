import '../../storage/database.dart';
import '../../storage/track_artists.dart';

class CoverflowItem {
  const CoverflowItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.artItemId,
    required this.tracks,
  });

  final String id;
  final String title;
  final String subtitle;
  final String artItemId;
  final List<Track> tracks;
}

List<CoverflowItem> trackCoverflowItems(List<Track> tracks) => [
  for (final track in tracks)
    CoverflowItem(
      id: 'track:${track.id}',
      title: track.name,
      subtitle: track.artist.isEmpty ? track.album : track.artist,
      artItemId: track.albumId ?? track.id,
      tracks: [track],
    ),
];

List<CoverflowItem> albumCoverflowItems(List<Track> tracks) {
  final groups = <String, List<Track>>{};
  final order = <String>[];
  for (final track in tracks) {
    if (track.album.isEmpty) continue;
    final key = track.albumId ?? 'album:${track.album}';
    if (!groups.containsKey(key)) order.add(key);
    (groups[key] ??= []).add(track);
  }
  final items = [
    for (final key in order)
      CoverflowItem(
        id: 'album:$key',
        title: groups[key]!.first.album,
        subtitle: _countLabel(groups[key]!.length),
        artItemId: groups[key]!.first.albumId ?? groups[key]!.first.id,
        tracks: List.unmodifiable(groups[key]!),
      ),
  ];
  items.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return items;
}

List<CoverflowItem> artistCoverflowItems(List<Track> tracks) {
  final groups = <String, _ArtistBucket>{};
  for (final track in tracks) {
    for (final credit in track.artistCredits) {
      final key = credit.id ?? 'name:${credit.name}';
      final bucket = groups[key] ??= _ArtistBucket(
        name: credit.name,
        tracks: [],
      );
      bucket.tracks.add(track);
    }
  }
  final items = [
    for (final entry in groups.entries)
      CoverflowItem(
        id: 'artist:${entry.key}',
        title: entry.value.name,
        subtitle: _countLabel(entry.value.tracks.length),
        artItemId:
            entry.value.tracks.first.albumId ?? entry.value.tracks.first.id,
        tracks: List.unmodifiable(entry.value.tracks),
      ),
  ];
  items.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return items;
}

String _countLabel(int count) => '$count ${count == 1 ? 'song' : 'songs'}';

class _ArtistBucket {
  _ArtistBucket({required this.name, required this.tracks});

  final String name;
  final List<Track> tracks;
}
