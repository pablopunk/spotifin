import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/services/playback/collection_queue.dart';
import 'package:spotifin/storage/database.dart';

void main() {
  test('shuffle off keeps the collection order and start', () {
    final queue = CollectionQueue.prepare(
      _tracks(4),
      shuffle: false,
      randomIndex: (_) => 2,
      startIndex: 1,
    );

    expect(queue.index, 1);
    expect(queue.context.map((track) => track.id), ['0', '1', '2', '3']);
  });

  test('shuffle off without a start plays the first song', () {
    final queue = CollectionQueue.prepare(
      _tracks(4),
      shuffle: false,
      randomIndex: (_) => 2,
    );

    expect(queue.index, 0);
  });

  test('shuffle on plays a random song first and keeps every song', () {
    final queue = CollectionQueue.prepare(
      _tracks(4),
      shuffle: true,
      randomIndex: (_) => 2,
    );

    expect(queue.index, 0);
    expect(queue.context.first.id, '2');
    expect(queue.context.map((track) => track.id), ['2', '3', '0', '1']);
  });

  test('shuffle on plays a chosen song first', () {
    final queue = CollectionQueue.prepare(
      _tracks(4),
      shuffle: true,
      randomIndex: (_) => 0,
      startIndex: 3,
    );

    expect(queue.index, 0);
    expect(queue.context.first.id, '3');
    expect(queue.context.map((track) => track.id), ['3', '0', '1', '2']);
  });
}

List<Track> _tracks(int count) => [
  for (var index = 0; index < count; index++)
    Track(
      id: '$index',
      name: 'Song $index',
      album: 'Album',
      artist: 'Artist',
      artistIds: '[]',
      labels: '[]',
      durationTicks: 10000000,
      favorite: false,
      playCount: 0,
      normalizationGain: null,
      albumNormalizationGain: null,
      container: 'mp3',
    ),
];
