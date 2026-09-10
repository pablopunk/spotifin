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
    'r&b': 'R&B/Soul',
    'r&b/soul': 'R&B/Soul',
    'rhythm and blues': 'R&B/Soul',
    'rnb': 'R&B/Soul',
    'soul': 'R&B/Soul',
    'electronic': 'Electronic',
    'electronica': 'Electronic',
    'rock': 'Rock',
    'indie rock': 'Rock',
    'pop rock': 'Rock',
    'punk': 'Punk',
    'pop punk': 'Punk',
    'punk rock': 'Punk',
  };

  List<DailyMix> generate(List<Track> catalog, DateTime day) {
    final tracksByLabel = <String, List<Track>>{};
    for (final track in catalog) {
      final labels = _labels(track)
          .map(_group)
          .where((label) => label.isNotEmpty);
      for (final label in labels.toSet()) {
        tracksByLabel.putIfAbsent(label, () => []).add(track);
      }
    }
    final groups =
        tracksByLabel.entries.where((entry) => entry.value.length >= 3).toList()
          ..sort((a, b) {
            final popularity = b.value.length.compareTo(a.value.length);
            return popularity != 0 ? popularity : a.key.compareTo(b.key);
          });
    return groups.take(4).map((group) {
      return DailyMix(
        name: '${group.key} mix',
        tracks: _select(group.value, day, group.key),
      );
    }).toList();
  }

  List<String> _labels(Track track) {
    try {
      return (jsonDecode(track.labels) as List<dynamic>).cast<String>();
    } on Object {
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
