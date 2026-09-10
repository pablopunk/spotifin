import 'dart:convert';
import 'dart:io';

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

  test('combines tags with shared words and matching word stems', () {
    final tracks = [
      _track('1', 'Artist A', ['rock'], 0),
      _track('2', 'Artist B', ['hard rock'], 0),
      _track('3', 'Artist C', ['indie rock'], 0),
      _track('4', 'Artist D', ['rock'], 0),
      _track('5', 'Artist E', ['electronic'], 0),
      _track('6', 'Artist F', ['electronica'], 0),
      _track('7', 'Artist G', ['electronic'], 0),
    ];

    final mixes = const MixGenerator().generate(tracks, DateTime(2026, 9, 10));

    expect(mixes.map((mix) => mix.name), ['Rock mix', 'Electronic mix']);
    expect(mixes.first.tracks, hasLength(4));
    expect(mixes.last.tracks, hasLength(3));
  });

  test('produces useful groups from the server tag distribution', () {
    final counts = (jsonDecode(
      File('test/fixtures/server_tag_counts.json').readAsStringSync(),
    ) as Map<String, dynamic>).cast<String, int>();
    var id = 0;
    final tracks = [
      for (final entry in counts.entries)
        for (var song = 0; song < entry.value; song++)
          _track('${id++}', 'Artist $id', [entry.key], 0),
    ];

    final mixes = const MixGenerator().generate(tracks, DateTime(2026, 9, 10));

    expect(mixes.map((mix) => mix.name), [
      'Rock mix',
      'Alternative mix',
      'Pop mix',
      'Punk mix',
    ]);
  });

  test('keeps only the four most common tag groups', () {
    const labels = ['ambient', 'blues', 'country', 'dance', 'folk'];
    final tracks = [
      for (var group = 0; group < labels.length; group++)
        for (var song = 0; song < group + 3; song++)
          _track('$group-$song', 'Artist $group-$song', [labels[group]], 0),
    ];

    final mixes = const MixGenerator().generate(tracks, DateTime(2026));

    expect(mixes, hasLength(4));
    expect(mixes.map((mix) => mix.name), [
      'Folk mix',
      'Dance mix',
      'Country mix',
      'Blues mix',
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
