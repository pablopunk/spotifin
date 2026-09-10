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

  List<DailyMix> generate(List<Track> catalog, DateTime day, {int? seed}) {
    final tracksByLabel = <String, List<Track>>{};
    for (final track in catalog) {
      final labels = _labels(track)
          .map(_normalize)
          .where((label) => label.isNotEmpty);
      for (final label in labels.toSet()) {
        tracksByLabel.putIfAbsent(label, () => []).add(track);
      }
    }
    final labels = tracksByLabel.entries.toList()
      ..sort((a, b) {
        final popularity = b.value.length.compareTo(a.value.length);
        return popularity != 0 ? popularity : a.key.compareTo(b.key);
      });
    final groups = <_TagGroup>[];
    for (final label in labels) {
      final matching = groups.indexWhere((group) => group.matches(label.key));
      if (matching < 0) {
        groups.add(_TagGroup(label.key, label.value));
      } else {
        groups[matching].add(label.value);
      }
    }
    groups.removeWhere((group) => group.tracks.length < 3);
    groups.sort((a, b) {
      final popularity = b.tracks.length.compareTo(a.tracks.length);
      return popularity != 0 ? popularity : a.label.compareTo(b.label);
    });
    if (groups.isEmpty) return const [];
    final minimumSize = math.max(3, (groups.first.tracks.length / 50).ceil());
    final random = _SeededRandom(
      _seedFor(day, seed ?? math.Random().nextInt(1 << 31)),
    );
    final selectedGroups = _weightedSample(
      groups.where((group) => group.tracks.length >= minimumSize).toList(),
      random,
    )..sort((a, b) => b.tracks.length.compareTo(a.tracks.length));
    return selectedGroups.map((group) {
      return DailyMix(
        name: '${_titleCase(group.label)} mix',
        tracks: _select(group.tracks.values.toList(), random, group.label),
      );
    }).toList();
  }

  List<_TagGroup> _weightedSample(
    List<_TagGroup> candidates,
    math.Random random,
  ) {
    final remaining = [...candidates];
    final selected = <_TagGroup>[];
    while (selected.length < 4 && remaining.isNotEmpty) {
      final totalWeight = remaining.fold<double>(
        0,
        (total, group) => total + math.sqrt(group.tracks.length),
      );
      var target = random.nextDouble() * totalWeight;
      var selectedIndex = remaining.length - 1;
      for (var index = 0; index < remaining.length; index++) {
        target -= math.sqrt(remaining[index].tracks.length);
        if (target < 0) {
          selectedIndex = index;
          break;
        }
      }
      selected.add(remaining.removeAt(selectedIndex));
    }
    return selected;
  }

  List<String> _labels(Track track) {
    try {
      return (jsonDecode(track.labels) as List<dynamic>).cast<String>();
    } on Object {
      return const [];
    }
  }

  String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  String _titleCase(String value) => value
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');

  List<Track> _select(List<Track> pool, math.Random random, String label) {
    final unique = {for (final track in pool) track.id: track}.values.toList();
    unique.sort((a, b) {
      final plays = b.playCount.compareTo(a.playCount);
      if (plays != 0) return plays;
      return a.id.compareTo(b.id);
    });
    final midpoint = (unique.length / 2).ceil();
    final frequent = unique.take(midpoint).toList();
    final lessPlayed = unique.skip(midpoint).toList();
    final seed = random.nextInt(1 << 31) ^ label.hashCode;
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

int _seedFor(DateTime day, int variation) =>
    (day.year * 10000 + day.month * 100 + day.day) ^ variation;

class _TagGroup {
  _TagGroup(this.label, List<Track> initial)
    : _tokens = _tagTokens(label),
      tracks = {for (final track in initial) track.id: track};

  final String label;
  final Set<String> _tokens;
  final Map<String, Track> tracks;

  bool matches(String candidate) {
    final candidateTokens = _tagTokens(candidate);
    if (_tokens.isEmpty || candidateTokens.isEmpty) return false;
    var matches = 0;
    for (final token in candidateTokens) {
      if (_tokens.any((existing) => _tokensMatch(existing, token))) matches++;
    }
    return matches * 2 >= math.min(_tokens.length, candidateTokens.length);
  }

  void add(List<Track> additions) {
    for (final track in additions) {
      tracks[track.id] = track;
    }
  }
}

Set<String> _tagTokens(String label) => label
    .split(RegExp(r'[^a-z0-9]+'))
    .where((token) => token.length > 1)
    .toSet();

bool _tokensMatch(String left, String right) {
  if (left == right) return true;
  final shorter = left.length <= right.length ? left : right;
  final longer = left.length <= right.length ? right : left;
  if (shorter.length < 5 || longer.length - shorter.length > 2) return false;
  return longer.startsWith(shorter.substring(0, shorter.length - 1));
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
