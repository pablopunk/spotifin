import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/services/mixes/mix_generator.dart';
import 'package:spotifin/storage/database.dart';

void main() {
  test('only includes songs directly tagged for the mix', () {
    final tracks = [
      _track('1', 'Artist A', ['Rock'], 20),
      _track('2', 'Artist A', [], 0),
      _track('3', 'Artist B', ['Rock'], 2),
      _track('4', 'Artist C', ['Rock'], 1),
    ];
    final mixes = const MixGenerator().generate(tracks, DateTime(2026, 9, 10));
    expect(mixes.single.name, 'Rock mix');
    expect(mixes.single.tracks.map((track) => track.id).toSet(), {
      '1',
      '3',
      '4',
    });
  });

  test('combines similar tags and ranks mixes by directly tagged songs', () {
    final tracks = [
      _track('1', 'Artist A', ['punk'], 0),
      _track('2', 'Artist B', ['pop punk'], 0),
      _track('3', 'Artist C', ['punk rock'], 0),
      _track('4', 'Artist D', ['punk'], 0),
      _track('5', 'Artist E', ['r&b'], 0),
      _track('6', 'Artist F', ['soul'], 0),
      _track('7', 'Artist G', ['R&B/Soul'], 0),
    ];

    final mixes = const MixGenerator().generate(tracks, DateTime(2026, 9, 10));

    expect(mixes.map((mix) => mix.name), ['Punk mix', 'R&B/Soul mix']);
    expect(mixes.first.tracks, hasLength(4));
    expect(mixes.last.tracks, hasLength(3));
  });

  test('keeps only the four most common tag groups', () {
    final tracks = [
      for (var group = 0; group < 5; group++)
        for (var song = 0; song < 3 + group; song++)
          _track('$group-$song', 'Artist $group-$song', ['genre $group'], 0),
    ];

    final mixes = const MixGenerator().generate(tracks, DateTime(2026));

    expect(mixes, hasLength(4));
    expect(mixes.map((mix) => mix.name), [
      'Genre 4 mix',
      'Genre 3 mix',
      'Genre 2 mix',
      'Genre 1 mix',
    ]);
  });

  test('does not invent a mix for untagged music', () {
    final tracks = [_track('1', 'Artist A', [], 0)];
    expect(const MixGenerator().generate(tracks, DateTime(2026)), isEmpty);
  });
}

Track _track(String id, String artist, List<String> labels, int plays) => Track(
  id: id,
  name: 'Song $id',
  album: 'Album',
  artist: artist,
  artistIds: '[]',
  labels: jsonEncode(labels),
  durationTicks: 10000000,
  favorite: false,
  playCount: plays,
  normalizationGain: null,
  albumNormalizationGain: null,
  container: 'mp3',
);
