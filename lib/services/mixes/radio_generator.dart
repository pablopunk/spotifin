import 'dart:convert';
import 'dart:math' as math;

import '../../storage/database.dart';

class RadioGenerator {
  const RadioGenerator({this.length = 50, this.maxPerAlbum = 5});

  final int length;
  final int maxPerAlbum;

  List<Track> generate(Track seed, List<Track> catalog, {math.Random? random}) {
    final seedLabels = _labels(seed);
    final candidates =
        catalog
            .where((track) => track.id != seed.id)
            .map((track) => (track, _score(seed, seedLabels, track)))
            .where((scored) => scored.$2 > 0)
            .toList()
          ..shuffle(random ?? math.Random());
    candidates.sort((a, b) => b.$2.compareTo(a.$2));
    final tracksPerAlbum = <String, int>{};
    final related = <Track>[];
    for (final (track, _) in candidates) {
      if (related.length >= length) break;
      final albumCount = tracksPerAlbum[_albumKey(track)] ?? 0;
      if (albumCount >= maxPerAlbum) continue;
      tracksPerAlbum[_albumKey(track)] = albumCount + 1;
      related.add(track);
    }
    related.shuffle(random ?? math.Random());
    return [seed, ...related];
  }

  int _score(Track seed, Set<String> seedLabels, Track track) {
    final sharedLabels = _labels(track).intersection(seedLabels).length;
    final sameArtist = track.artist == seed.artist ? 2 : 0;
    return sharedLabels * 3 + sameArtist;
  }

  String _albumKey(Track track) => track.albumId ?? track.album;

  Set<String> _labels(Track track) {
    try {
      return (jsonDecode(track.labels) as List<dynamic>)
          .cast<String>()
          .map((label) => label.trim().toLowerCase())
          .where((label) => label.isNotEmpty)
          .toSet();
    } on Object {
      return const {};
    }
  }
}
