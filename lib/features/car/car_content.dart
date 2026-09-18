import 'dart:convert';

import '../../storage/database.dart';
import 'car_media_ids.dart';

enum CarSection { recents, favorites, playlists, artists, songs }

class CarTrackRef {
  const CarTrackRef({
    required this.id,
    required this.title,
    required this.subtitle,
  });

  factory CarTrackRef.fromTrack(Track track) => CarTrackRef(
    id: track.id,
    title: track.name,
    subtitle: carSubtitle(track),
  );

  final String id;
  final String title;
  final String subtitle;
}

class CarGroup {
  const CarGroup({
    required this.id,
    required this.title,
    required this.trackCount,
  });

  final String id;
  final String title;
  final int trackCount;
}

class CarCatalogSnapshot {
  const CarCatalogSnapshot({this.tracks = const [], this.playlists = const []});

  final List<Track> tracks;
  final List<Playlist> playlists;
}

String carSubtitle(Track track) =>
    joinCarSegments([hideUnknownArtist(track.artist), track.album.trim()]);

String joinCarSegments(List<String> segments) =>
    segments.where((segment) => segment.isNotEmpty).join(' • ');

String hideUnknownArtist(String artist) {
  final trimmed = artist.trim();
  if (trimmed.isEmpty || trimmed == 'Unknown artist') return '';
  return trimmed;
}

DateTime? carRecencyOf(Track track) =>
    track.lastPlayed ?? track.dateCreated ?? track.premiereDate;

List<CarTrackRef> buildRecents(List<Track> tracks, {int limit = 25}) {
  final sorted = List<Track>.of(tracks)
    ..sort((a, b) {
      final aDate = carRecencyOf(a);
      final bDate = carRecencyOf(b);
      if (aDate == null && bDate == null) return a.name.compareTo(b.name);
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      final cmp = bDate.compareTo(aDate);
      return cmp != 0 ? cmp : a.name.compareTo(b.name);
    });
  return sorted.take(limit).map(CarTrackRef.fromTrack).toList();
}

List<CarTrackRef> buildFavorites(List<Track> tracks, {int limit = 50}) {
  final favorites = tracks.where((track) => track.favorite).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  return favorites.take(limit).map(CarTrackRef.fromTrack).toList();
}

List<CarGroup> groupArtists(List<Track> tracks, {int limit = 50}) {
  final counts = <String, int>{};
  for (final track in tracks) {
    final name = track.artist.trim();
    if (name.isEmpty || name == 'Unknown artist') continue;
    counts[name] = (counts[name] ?? 0) + 1;
  }
  final groups =
      counts.entries
          .map(
            (entry) => CarGroup(
              id: carArtistId(entry.key),
              title: entry.key,
              trackCount: entry.value,
            ),
          )
          .toList()
        ..sort(_compareGroups);
  return groups.take(limit).toList();
}

List<CarGroup> groupAlbums(List<Track> tracks, {int limit = 50}) {
  final counts = <String, int>{};
  final titles = <String, String>{};
  for (final track in tracks) {
    final title = track.album.trim();
    if (title.isEmpty) continue;
    final key = track.albumId?.trim().isNotEmpty == true
        ? track.albumId!.trim()
        : 'name::$title';
    counts[key] = (counts[key] ?? 0) + 1;
    titles.putIfAbsent(key, () => title);
  }
  final groups =
      counts.entries
          .map(
            (entry) => CarGroup(
              id: carAlbumId(entry.key),
              title: titles[entry.key] ?? entry.key,
              trackCount: entry.value,
            ),
          )
          .toList()
        ..sort(_compareGroups);
  return groups.take(limit).toList();
}

int _compareGroups(CarGroup a, CarGroup b) {
  final count = b.trackCount.compareTo(a.trackCount);
  return count != 0 ? count : a.title.compareTo(b.title);
}

List<Track> tracksForArtist(List<Track> tracks, String artistName) {
  final matches =
      tracks.where((track) => track.artist.trim() == artistName.trim()).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
  return matches;
}

List<Track> tracksForAlbum(List<Track> tracks, String albumKey) {
  final matches = tracks.where((track) {
    if (track.albumId?.trim().isNotEmpty == true) {
      return track.albumId!.trim() == albumKey;
    }
    return 'name::${track.album.trim()}' == albumKey ||
        track.album.trim() == albumKey;
  }).toList()..sort((a, b) => a.name.compareTo(b.name));
  return matches;
}

List<String> playlistTrackIds(Playlist playlist) {
  try {
    return (jsonDecode(playlist.trackIds) as List<dynamic>).cast<String>();
  } catch (_) {
    return const [];
  }
}

List<Track> playlistChildren(
  Playlist playlist,
  Map<String, Track> byId, {
  int limit = 50,
}) {
  final children = <Track>[];
  for (final id in playlistTrackIds(playlist)) {
    final track = byId[id];
    if (track != null) children.add(track);
    if (children.length >= limit) break;
  }
  return children;
}

List<CarTrackRef> searchCatalog(
  List<Track> tracks,
  String query, {
  int limit = 25,
}) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return const [];
  final matches = tracks.where((track) {
    return track.name.toLowerCase().contains(needle) ||
        track.artist.toLowerCase().contains(needle) ||
        track.album.toLowerCase().contains(needle);
  }).toList()..sort((a, b) => a.name.compareTo(b.name));
  return matches.take(limit).map(CarTrackRef.fromTrack).toList();
}
