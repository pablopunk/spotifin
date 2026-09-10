import 'dart:convert';
import 'dart:math' as math;

import '../../storage/database.dart';

class DailyMix {
  const DailyMix({required this.name, required this.tracks});
  final String name;
  final List<Track> tracks;
}

class MixGenerator {
  const MixGenerator();

  static const _aliases = {
    'hip hop': 'Hip-Hop',
    'hip-hop': 'Hip-Hop',
    'rap': 'Hip-Hop',
    'r&b': 'R&B',
    'rhythm and blues': 'R&B',
    'electronic': 'Electronic',
    'electronica': 'Electronic',
    'rock': 'Rock',
    'indie rock': 'Rock',
  };

  List<DailyMix> generate(List<Track> catalog, DateTime day) {
    final artistsByLabel = <String, Set<String>>{};
    for (final track in catalog) {
      for (final raw in _labels(track)) {
        final label = _group(raw);
        artistsByLabel.putIfAbsent(label, () => {}).add(track.artist);
      }
    }
    final mixes = artistsByLabel.entries
        .where((entry) => entry.value.isNotEmpty)
        .map((entry) {
          final pool = catalog
              .where((track) => entry.value.contains(track.artist))
              .toList();
          return DailyMix(
            name: '${entry.key} mix',
            tracks: _select(pool, day, entry.key),
          );
        })
        .where((mix) => mix.tracks.length >= 3)
        .toList();
    mixes.sort((a, b) => b.tracks.length.compareTo(a.tracks.length));
    return mixes.take(6).toList();
  }

  List<String> _labels(Track track) {
    try {
      return (jsonDecode(track.labels) as List<dynamic>).cast<String>();
    } on FormatException {
      return const [];
    }
  }

  String _group(String value) {
    final normalized = value.trim().toLowerCase();
    return _aliases[normalized] ?? _titleCase(normalized);
  }

  String _titleCase(String value) => value
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');

  List<Track> _select(List<Track> pool, DateTime day, String label) {
    final unique = {for (final track in pool) track.id: track}.values.toList();
    unique.sort((a, b) {
      final plays = b.playCount.compareTo(a.playCount);
      if (plays != 0) return plays;
      return a.id.compareTo(b.id);
    });
    final midpoint = (unique.length / 2).ceil();
    final frequent = unique.take(midpoint).toList();
    final lessPlayed = unique.skip(midpoint).toList();
    final seed = day.year * 10000 + day.month * 100 + day.day + label.hashCode;
    frequent.shuffle(_SeededRandom(seed));
    lessPlayed.shuffle(_SeededRandom(seed ^ 0x5f3759df));
    final result = <Track>[];
    while (result.length < 50 &&
        (frequent.isNotEmpty || lessPlayed.isNotEmpty)) {
      if (frequent.isNotEmpty) result.add(frequent.removeLast());
      if (result.length < 50 && lessPlayed.isNotEmpty) {
        result.add(lessPlayed.removeLast());
      }
    }
    return result;
  }
}

class _SeededRandom implements math.Random {
  _SeededRandom(this._state);
  int _state;

  @override
  bool nextBool() => nextInt(2) == 0;

  @override
  double nextDouble() => nextInt(1 << 26) / (1 << 26);

  @override
  int nextInt(int max) {
    if (max <= 0) throw ArgumentError.value(max, 'max');
    _state = (_state * 1664525 + 1013904223) & 0x7fffffff;
    return _state % max;
  }
}
