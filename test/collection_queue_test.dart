import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/services/playback/collection_queue.dart';
import 'package:spotifin/storage/database.dart';

void main() {
  test('shuffle off keeps the collection order and start', () {
    final queue = CollectionQueue.prepare(
      _tracks(4),
      shuffle: false,
      startIndex: 1,
    );

    expect(queue.index, 1);
    expect(queue.context.map((track) => track.id), ['0', '1', '2', '3']);
  });

  test('shuffle off without a start plays the first song', () {
    final queue = CollectionQueue.prepare(_tracks(4), shuffle: false);

    expect(queue.index, 0);
  });

  test('empty collection stays empty', () {
    final queue = CollectionQueue.prepare(
      const [],
      shuffle: true,
      random: Random(1),
    );

    expect(queue.context, isEmpty);
    expect(queue.index, 0);
  });

  test('shuffle on plays a chosen song first and shuffles the rest', () {
    final queue = CollectionQueue.prepare(
      _tracks(5),
      shuffle: true,
      random: Random(42),
      startIndex: 3,
    );

    expect(queue.index, 0);
    expect(queue.context.first.id, '3');
    expect(queue.context.map((track) => track.id).toSet(), {
      '0',
      '1',
      '2',
      '3',
      '4',
    });
    expect(queue.context.length, 5);
  });

  test('shuffle on without a start is deterministic for a seed', () {
    final first = CollectionQueue.prepare(
      _tracks(6),
      shuffle: true,
      random: Random(7),
    );
    final second = CollectionQueue.prepare(
      _tracks(6),
      shuffle: true,
      random: Random(7),
    );

    expect(
      first.context.map((track) => track.id),
      second.context.map((track) => track.id),
    );
    expect(first.context.map((track) => track.id).toSet(), {
      '0',
      '1',
      '2',
      '3',
      '4',
      '5',
    });
  });

  test('shuffleRemainder keeps the queue length and shuffles jointly', () {
    final queueSuffix = _tracks(3);
    final idSuffix = ['id-0', 'id-1', 'id-2'];
    final tail = _tracks(3)
        .sublist(0, 2)
        .map(
          (track) => Track(
            id: 'tail-${track.id}',
            name: track.name,
            album: track.album,
            artist: track.artist,
            artistItems: '[]',
            labels: '[]',
            durationTicks: 10000000,
            favorite: false,
            playCount: 0,
            normalizationGain: null,
            albumNormalizationGain: null,
            container: 'mp3',
          ),
        )
        .toList();
    var counter = 0;

    final result = CollectionQueue.shuffleRemainder(
      queueSuffix: queueSuffix,
      idSuffix: idSuffix,
      tail: tail,
      random: Random(11),
      newId: () => 'new-${counter++}',
    );

    expect(result.queueTracks.length, 3);
    expect(result.queueIds.length, 3);
    expect(result.queueIds.toSet().length, 3);
    final combinedBefore = {
      ...queueSuffix.map((track) => track.id),
      ...tail.map((track) => track.id),
    };
    final combinedAfter = {
      ...result.queueTracks.map((track) => track.id),
      ...result.tail.map((track) => track.id),
    };
    expect(combinedAfter, combinedBefore);
  });
}

List<Track> _tracks(int count) => [
  for (var index = 0; index < count; index++)
    Track(
      id: '$index',
      name: 'Song $index',
      album: 'Album',
      artist: 'Artist',
      artistItems: '[]',
      labels: '[]',
      durationTicks: 10000000,
      favorite: false,
      playCount: 0,
      normalizationGain: null,
      albumNormalizationGain: null,
      container: 'mp3',
    ),
];
