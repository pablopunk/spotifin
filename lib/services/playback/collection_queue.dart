import 'dart:math' as math;

import '../../storage/database.dart';

class CollectionQueue {
  const CollectionQueue({required this.context, required this.index});

  final List<Track> context;
  final int index;

  factory CollectionQueue.prepare(
    List<Track> tracks, {
    required bool shuffle,
    math.Random? random,
    int? startIndex,
  }) {
    if (tracks.isEmpty) {
      return const CollectionQueue(context: [], index: 0);
    }
    if (!shuffle) {
      final index = (startIndex ?? 0).clamp(0, tracks.length - 1);
      return CollectionQueue(context: List.of(tracks), index: index);
    }
    final rng = random ?? math.Random();
    final remaining = List.of(tracks);
    final requested = startIndex ?? rng.nextInt(remaining.length);
    final clamped = requested.clamp(0, remaining.length - 1);
    final first = remaining.removeAt(clamped);
    remaining.shuffle(rng);
    return CollectionQueue(context: [first, ...remaining], index: 0);
  }

  static RemainderShuffle shuffleRemainder({
    required List<Track> queueSuffix,
    required List<String> idSuffix,
    required List<Track> tail,
    required math.Random random,
    required String Function() newId,
  }) {
    assert(queueSuffix.length == idSuffix.length);
    final entries = <_RemainderEntry>[
      for (var index = 0; index < queueSuffix.length; index++)
        _RemainderEntry(queueSuffix[index], idSuffix[index]),
      for (final track in tail) _RemainderEntry(track, null),
    ];
    entries.shuffle(random);
    final queueLength = queueSuffix.length;
    final shuffledQueue = entries.sublist(0, queueLength);
    final shuffledTail = entries.sublist(queueLength);
    return RemainderShuffle(
      queueTracks: [for (final entry in shuffledQueue) entry.track],
      queueIds: [for (final entry in shuffledQueue) entry.id ?? newId()],
      tail: [for (final entry in shuffledTail) entry.track],
    );
  }
}

class RemainderShuffle {
  const RemainderShuffle({
    required this.queueTracks,
    required this.queueIds,
    required this.tail,
  });

  final List<Track> queueTracks;
  final List<String> queueIds;
  final List<Track> tail;
}

class _RemainderEntry {
  _RemainderEntry(this.track, this.id);

  final Track track;
  final String? id;
}
