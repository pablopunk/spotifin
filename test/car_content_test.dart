import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/features/car/car_content.dart';
import 'package:spotifin/storage/database.dart';

Track makeTrack({
  required String id,
  String name = 'Song',
  String album = 'Album',
  String? albumId,
  String artist = 'Artist',
  bool favorite = false,
  DateTime? lastPlayed,
  DateTime? dateCreated,
  DateTime? premiereDate,
}) => Track(
  id: id,
  name: name,
  album: album,
  albumId: albumId,
  artist: artist,
  artistItems: '[]',
  labels: '[]',
  durationTicks: 0,
  container: 'mp3',
  favorite: favorite,
  playCount: 0,
  lastPlayed: lastPlayed,
  dateCreated: dateCreated,
  premiereDate: premiereDate,
);

Playlist makePlaylist(String id, String name, List<String> trackIds) =>
    Playlist(id: id, name: name, trackIds: jsonEncode(trackIds));

void main() {
  test('recents sort by lastPlayed then dateCreated then premiereDate', () {
    final old = makeTrack(id: 'old', dateCreated: DateTime(2020));
    final recent = makeTrack(id: 'recent', lastPlayed: DateTime(2026));
    final middle = makeTrack(id: 'middle', dateCreated: DateTime(2024));
    final undated = makeTrack(id: 'undated');

    final ids = buildRecents([undated, old, recent, middle])
        .map((ref) => ref.id)
        .toList();

    expect(ids, ['recent', 'middle', 'old', 'undated']);
  });

  test('recents are capped', () {
    final tracks = List.generate(
      30,
      (i) => makeTrack(id: 't$i', lastPlayed: DateTime(2026, 1, i + 1)),
    );
    expect(buildRecents(tracks).length, 25);
  });

  test('favorites filter and sort by name', () {
    final tracks = [
      makeTrack(id: 'b', name: 'Bravo', favorite: true),
      makeTrack(id: 'a', name: 'Alpha', favorite: true),
      makeTrack(id: 'c', name: 'Charlie'),
    ];
    final ids = buildFavorites(tracks).map((ref) => ref.id).toList();
    expect(ids, ['a', 'b']);
  });

  test('recently added matches library ordering', () {
    final tracks = [
      makeTrack(id: 'undated-z', name: 'Zulu'),
      makeTrack(id: 'old', name: 'Old', dateCreated: DateTime(2024)),
      makeTrack(id: 'same-b', name: 'Bravo', dateCreated: DateTime(2026)),
      makeTrack(id: 'same-a', name: 'Alpha', dateCreated: DateTime(2026)),
      makeTrack(id: 'undated-a', name: 'Alpha'),
    ];

    expect(buildRecentlyAdded(tracks).map((track) => track.id), [
      'same-a',
      'same-b',
      'old',
      'undated-a',
      'undated-z',
    ]);
  });

  test('artist groups skip unknown artists', () {
    final tracks = [
      makeTrack(id: '1', artist: 'Miles'),
      makeTrack(id: '2', artist: 'Miles'),
      makeTrack(id: '3', artist: 'Unknown artist'),
      makeTrack(id: '4', artist: ''),
      makeTrack(id: '5', artist: 'Coltrane'),
    ];
    final groups = groupArtists(tracks);
    expect(groups.map((group) => group.title), ['Miles', 'Coltrane']);
    expect(groups.first.trackCount, 2);
  });

  test('album groups key on albumId when present', () {
    final tracks = [
      makeTrack(id: '1', album: 'Blue', albumId: 'a1'),
      makeTrack(id: '2', album: 'Blue Deluxe', albumId: 'a1'),
      makeTrack(id: '3', album: 'Giant Steps'),
    ];
    final groups = groupAlbums(tracks);
    expect(groups.length, 2);
    expect(groups.firstWhere((group) => group.title == 'Blue').trackCount, 2);
  });

  test('playlist children drop unknown ids and keep order', () {
    final byId = {
      'a': makeTrack(id: 'a', name: 'A'),
      'b': makeTrack(id: 'b', name: 'B'),
    };
    final playlist = makePlaylist('p', 'Mix', ['a', 'missing', 'b']);
    final children = playlistChildren(playlist, byId);
    expect(children.map((track) => track.id), ['a', 'b']);
  });

  test('malformed playlist payload resolves to empty', () {
    const playlist = Playlist(id: 'p', name: 'Mix', trackIds: 'nope');
    expect(playlistChildren(playlist, const {}), isEmpty);
  });

  test('search is case-insensitive and capped, empty returns empty', () {
    final tracks = List.generate(
      30,
      (i) => makeTrack(id: 't$i', name: 'Love Song $i', artist: 'Band'),
    );
    expect(searchCatalog(tracks, ''), isEmpty);
    expect(searchCatalog(tracks, '  '), isEmpty);
    final matches = searchCatalog(tracks, 'LOVE');
    expect(matches.length, 25);
    final none = searchCatalog(tracks, 'xyz-no-match');
    expect(none, isEmpty);
  });

  test('search is accent-insensitive: rosalia matches ROSALÍA', () {
    final tracks = [
      makeTrack(id: 'unrelated', name: 'Metal Song', artist: 'Band'),
      makeTrack(id: 'rosalia', name: 'Con Altura', artist: 'ROSALÍA'),
    ];
    final matches = searchCatalog(tracks, 'rosalia');
    expect(matches.map((ref) => ref.id), ['rosalia']);
    expect(searchCatalog(tracks, 'ROSALÍA').map((ref) => ref.id), ['rosalia']);
  });

  test('search ranks exact title matches above typo matches', () {
    final tracks = [
      makeTrack(id: 'typo', name: 'Rosaila Ballad', artist: 'Band'),
      makeTrack(id: 'exact', name: 'Rosalia Anthem', artist: 'Band'),
    ];
    final matches = searchCatalog(tracks, 'rosalia');
    expect(matches.map((ref) => ref.id), ['exact', 'typo']);
  });

  test('track subtitle omits unknown artist', () {
    final known = makeTrack(id: 'k', name: 'N', artist: 'Miles', album: 'Blue');
    final unknown = makeTrack(
      id: 'u',
      name: 'N',
      artist: 'Unknown artist',
      album: 'Blue',
    );
    expect(CarTrackRef.fromTrack(known).subtitle, 'Miles • Blue');
    expect(CarTrackRef.fromTrack(unknown).subtitle, 'Blue');
  });
}
