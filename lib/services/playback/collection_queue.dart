import '../../storage/database.dart';

class CollectionQueue {
  const CollectionQueue({required this.context, required this.index});

  final List<Track> context;
  final int index;

  factory CollectionQueue.prepare(
    List<Track> tracks, {
    required bool shuffle,
    required int Function(int max) randomIndex,
    int? startIndex,
  }) {
    final requested = startIndex ?? (shuffle ? randomIndex(tracks.length) : 0);
    final index = requested.clamp(0, tracks.length - 1);
    if (!shuffle) {
      return CollectionQueue(context: List.of(tracks), index: index);
    }
    return CollectionQueue(context: _rotated(tracks, index), index: 0);
  }
}

List<Track> _rotated(List<Track> tracks, int start) => [
  ...tracks.skip(start),
  ...tracks.take(start),
];
