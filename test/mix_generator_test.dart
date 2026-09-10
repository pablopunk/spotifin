import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/services/mixes/mix_generator.dart';
import 'package:spotifin/storage/database.dart';

void main() {
  test('expands labels to all songs from matching artists', () {
    final tracks = [
      _track('1', 'Artist A', ['Rock'], 20),
      _track('2', 'Artist A', [], 0),
      _track('3', 'Artist B', ['Rock'], 2),
      _track('4', 'Artist B', [], 1),
    ];
    final mixes = const MixGenerator().generate(tracks, DateTime(2026, 9, 10));
    expect(mixes.single.name, 'Rock mix');
    expect(mixes.single.tracks.map((track) => track.id).toSet(), {
      '1',
      '2',
      '3',
      '4',
    });
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
);
