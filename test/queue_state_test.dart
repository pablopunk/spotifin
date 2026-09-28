import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/services/playback/queue_state.dart';
import 'package:spotifin/storage/database.dart';

void main() {
  group('QueueState factories', () {
    test('empty has zero bounds and null index', () {
      final state = QueueState.empty();

      expect(state.entries, isEmpty);
      expect(state.loadedEntries, isEmpty);
      expect(state.windowStart, 0);
      expect(state.windowEnd, 0);
      expect(state.currentIndex, isNull);
      expect(state.currentEntry, isNull);
      expect(state.shuffle, isFalse);
      expect(state.hasUnloadedTail, isFalse);
      expect(state.upcomingTracks, isEmpty);
    });

    test('prepare with empty input stays empty', () {
      final state = QueueState.prepare(
        const [],
        shuffle: true,
        random: Random(1),
        newId: _ids(),
      );

      expect(state.entries, isEmpty);
      expect(state.currentIndex, isNull);
    });

    test('prepare windows 250 tracks with look-behind', () {
      final tracks = _tracks(250);
      final state = QueueState.prepare(
        tracks,
        startIndex: 120,
        shuffle: false,
        newId: _ids(),
      );

      expect(state.entries.map((entry) => entry.track.id).toList(), [
        for (var index = 0; index < 250; index++) '$index',
      ]);
      expect(state.windowStart, 100);
      expect(state.windowEnd, 200);
      expect(state.currentIndex, 20);
      expect(state.currentEntry?.track.id, '120');
      expect(state.loadedEntries.length, 100);
      expect(state.hasUnloadedTail, isTrue);
      expect(state.upcomingTracks.first.id, '120');
      expect(state.upcomingTracks.length, 80);
    });

    test('prepare near the start keeps a full window', () {
      final state = QueueState.prepare(
        _tracks(250),
        startIndex: 5,
        shuffle: false,
        newId: _ids(),
      );

      expect(state.windowStart, 0);
      expect(state.windowEnd, 100);
      expect(state.currentIndex, 5);
    });

    test('prepare with shuffle uses collection ordering', () {
      final first = QueueState.prepare(
        _tracks(10),
        startIndex: 3,
        shuffle: true,
        random: Random(42),
        newId: _ids(),
      );
      final second = QueueState.prepare(
        _tracks(10),
        startIndex: 3,
        shuffle: true,
        random: Random(42),
        newId: _ids(),
      );

      expect(first.currentEntry?.track.id, '3');
      expect(
        first.entries.map((entry) => entry.track.id),
        second.entries.map((entry) => entry.track.id),
      );
      expect(first.shuffle, isTrue);
    });

    test('duplicate tracks receive distinct occurrence ids', () {
      final track = _tracks(1).single;
      final state = QueueState.prepare(
        [track, track, track],
        shuffle: false,
        newId: _ids(),
      );

      final ids = state.entries.map((entry) => entry.id).toList();
      expect(ids.toSet().length, 3);
      expect(state.entries.map((entry) => entry.track.id), ['0', '0', '0']);
    });

    test('restore loads every track and clamps the index', () {
      final low = QueueState.restore(
        _tracks(5),
        index: -4,
        shuffle: false,
        newId: _ids(),
      );
      final high = QueueState.restore(
        _tracks(5),
        index: 99,
        shuffle: true,
        newId: _ids(),
      );

      expect(low.loadedEntries.length, 5);
      expect(low.hasUnloadedTail, isFalse);
      expect(low.currentIndex, 0);
      expect(high.currentIndex, 4);
      expect(high.shuffle, isTrue);
      expect(high.entries.map((entry) => entry.id).toSet().length, 5);
    });

    test('input list mutation cannot alter a state', () {
      final tracks = _tracks(3);
      final state = QueueState.prepare(tracks, shuffle: false, newId: _ids());
      tracks.clear();

      expect(state.entries.length, 3);
      expect(state.loadedEntries.length, 3);
    });

    test('exposed lists are unmodifiable', () {
      final state = QueueState.prepare(
        _tracks(3),
        shuffle: false,
        newId: _ids(),
      );

      expect(
        () => state.entries.add(state.entries.first),
        throwsUnsupportedError,
      );
      expect(() => state.loadedEntries.removeAt(0), throwsUnsupportedError);
    });
  });

  group('QueueState manual edits', () {
    test('append stops expansion and adds a distinct occurrence', () {
      final state = QueueState.prepare(
        _tracks(250),
        startIndex: 120,
        shuffle: false,
        newId: _ids(),
      );
      final extra = _tracks(1).single;
      final next = state.append(extra, newId: _ids('append-'));

      expect(state.hasUnloadedTail, isTrue);
      expect(next.hasUnloadedTail, isFalse);
      expect(next.windowStart, 0);
      expect(next.entries.length, 101);
      expect(next.entries.last.track.id, '0');
      expect(next.entries.last.id.startsWith('append-'), isTrue);
      expect(next.currentEntry?.track.id, '120');
      expect(next.currentEntry?.id, state.currentEntry?.id);
      // Original state did not change.
      expect(state.windowStart, 100);
      expect(state.entries.length, 250);
    });

    test('insertNext inserts after current or at zero', () {
      final state = QueueState.prepare(
        _tracks(10),
        startIndex: 2,
        shuffle: false,
        newId: _ids(),
      );
      final inserted = state.insertNext([
        _track('new-1'),
        _track('new-2'),
      ], newId: _ids());

      expect(inserted.loadedTracks.map((track) => track.id), [
        '0',
        '1',
        '2',
        'new-1',
        'new-2',
        '3',
        '4',
        '5',
        '6',
        '7',
        '8',
        '9',
      ]);
      expect(inserted.currentEntry?.track.id, '2');
      expect(inserted.hasUnloadedTail, isFalse);

      final noCurrent = QueueState.restore(
        _tracks(3),
        index: 0,
        shuffle: false,
        newId: _ids(),
      ).selectEntry('missing');
      final atZero = noCurrent.removeAt(0).removeAt(0).removeAt(0);
      expect(atZero.currentIndex, isNull);
      final prepended = atZero.insertNext([_track('first')], newId: _ids());
      expect(prepended.loadedTracks.map((track) => track.id), ['first']);
    });

    test('removeAt preserves current and handles the current removal', () {
      final state = QueueState.prepare(
        _tracks(5),
        startIndex: 2,
        shuffle: false,
        newId: _ids(),
      );

      final before = state.removeAt(0);
      expect(before.loadedTracks.map((track) => track.id), [
        '1',
        '2',
        '3',
        '4',
      ]);
      expect(before.currentIndex, 1);
      expect(before.currentEntry?.track.id, '2');

      final current = state.removeAt(2);
      expect(current.loadedTracks.map((track) => track.id), [
        '0',
        '1',
        '3',
        '4',
      ]);
      expect(current.currentEntry?.track.id, '3');

      final last = QueueState.prepare(
        _tracks(2),
        startIndex: 1,
        shuffle: false,
        newId: _ids(),
      ).removeAt(1);
      expect(last.currentEntry?.track.id, '0');

      final emptied = QueueState.prepare(
        _tracks(1),
        shuffle: false,
        newId: _ids(),
      ).removeAt(0);
      expect(emptied.entries, isEmpty);
      expect(emptied.currentIndex, isNull);
    });

    test('removeAt with invalid indices keeps the tail', () {
      final state = QueueState.prepare(
        _tracks(250),
        startIndex: 120,
        shuffle: false,
        newId: _ids(),
      );

      expect(identical(state.removeAt(-1), state), isTrue);
      expect(identical(state.removeAt(500), state), isTrue);
      expect(state.hasUnloadedTail, isTrue);
    });

    test('removeTrack removes all occurrences and keeps current by id', () {
      final track = _track('dup');
      final state = QueueState.prepare(
        [_track('a'), track, _track('b'), track, _track('c')],
        startIndex: 3,
        shuffle: false,
        newId: _ids(),
      );
      final currentId = state.currentEntry?.id;

      final kept = state.removeTrack('missing');
      expect(identical(kept, state), isTrue);

      final removed = state.removeTrack('dup');
      expect(removed.loadedTracks.map((track) => track.id), ['a', 'b', 'c']);
      // Current occurrence was removed: successor selected.
      expect(removed.currentEntry?.track.id, 'c');

      final keepCurrent = QueueState.prepare(
        [_track('a'), track, _track('b')],
        startIndex: 0,
        shuffle: false,
        newId: _ids(),
      ).removeTrack('dup');
      expect(keepCurrent.currentEntry?.track.id, 'a');
      expect(currentId, isNotNull);
    });

    test('reorder preserves the current occurrence by id', () {
      final state = QueueState.prepare(
        _tracks(5),
        startIndex: 1,
        shuffle: false,
        newId: _ids(),
      );
      final currentId = state.currentEntry?.id;

      final moved = state.reorder(0, 4);
      expect(moved.loadedTracks.map((track) => track.id), [
        '1',
        '2',
        '3',
        '4',
        '0',
      ]);
      expect(moved.currentEntry?.id, currentId);
      expect(moved.currentEntry?.track.id, '1');

      expect(identical(state.reorder(-1, 2), state), isTrue);
      expect(identical(state.reorder(1, 9), state), isTrue);
    });

    test('selectEntry selects a loaded occurrence by id', () {
      final state = QueueState.prepare(
        _tracks(5),
        startIndex: 0,
        shuffle: false,
        newId: _ids(),
      );
      final target = state.entries[3];

      final selected = state.selectEntry(target.id);
      expect(selected.currentIndex, 3);
      expect(selected.currentEntry?.id, target.id);
      expect(identical(state.selectEntry('unknown'), state), isTrue);
    });
  });

  group('QueueState shuffle and extension', () {
    test('shuffleRemaining keeps prefix and window size', () {
      final state = QueueState.prepare(
        _tracks(250),
        startIndex: 120,
        shuffle: false,
        newId: _ids(),
      );
      final beforeIds = state.entries.map((entry) => entry.id).toList();
      final shuffled = state.shuffleRemaining(random: Random(7));

      expect(shuffled.windowStart, state.windowStart);
      expect(shuffled.windowEnd, state.windowEnd);
      expect(shuffled.currentIndex, state.currentIndex);
      expect(shuffled.currentEntry?.id, state.currentEntry?.id);
      // Loaded prefix through current is untouched.
      expect(
        shuffled.loadedEntries
            .sublist(0, state.currentIndex! + 1)
            .map((entry) => entry.id),
        state.loadedEntries
            .sublist(0, state.currentIndex! + 1)
            .map((entry) => entry.id),
      );
      // Every entry id is preserved exactly once.
      expect(
        shuffled.entries.map((entry) => entry.id).toSet(),
        beforeIds.toSet(),
      );
      expect(shuffled.entries.length, 250);
    });

    test('seeded shuffle is deterministic', () {
      QueueState shuffle() => QueueState.prepare(
        _tracks(60),
        startIndex: 10,
        shuffle: false,
        newId: _ids(),
      ).shuffleRemaining(random: Random(3));

      expect(
        shuffle().entries.map((entry) => entry.id),
        shuffle().entries.map((entry) => entry.id),
      );
    });

    test('shuffle after each manual edit keeps a valid prefix', () {
      final extra = _track('extra');
      final base = QueueState.prepare(
        _tracks(150),
        startIndex: 60,
        shuffle: false,
        newId: _ids(),
      );
      final edited = [
        base.append(extra, newId: _ids()),
        base.insertNext([extra], newId: _ids()),
        base.removeAt(10),
        base.removeTrack('5'),
        base.reorder(0, 9),
      ];
      for (final state in edited) {
        final shuffled = state.shuffleRemaining(random: Random(9));
        expect(shuffled.hasUnloadedTail, isFalse);
        expect(shuffled.loadedEntries.length, state.loadedEntries.length);
        expect(shuffled.currentEntry?.id, state.currentEntry?.id);
      }
    });

    test('one-track queue and current at final index', () {
      final single = QueueState.prepare(
        _tracks(1),
        shuffle: false,
        newId: _ids(),
      ).shuffleRemaining(random: Random(1));
      expect(single.loadedEntries.length, 1);
      expect(single.currentIndex, 0);

      final atEnd = QueueState.prepare(
        _tracks(30),
        startIndex: 29,
        shuffle: false,
        newId: _ids(),
      );
      final shuffledEnd = atEnd.shuffleRemaining(random: Random(2));
      expect(shuffledEnd.currentEntry?.track.id, '29');
      expect(shuffledEnd.loadedEntries.length, atEnd.loadedEntries.length);
    });

    test('extend loads the tail without new ids', () {
      final state = QueueState.prepare(
        _tracks(250),
        startIndex: 120,
        shuffle: false,
        newId: _ids(),
      );
      final beforeIds = state.loadedEntries.map((entry) => entry.id).toList();
      final extended = state.extend();

      expect(extended.windowEnd, 250);
      expect(extended.currentIndex, state.currentIndex);
      expect(
        extended.loadedEntries
            .sublist(0, beforeIds.length)
            .map((entry) => entry.id),
        beforeIds,
      );
      expect(extended.hasUnloadedTail, isFalse);
      expect(identical(extended.extend(), extended), isTrue);
    });

    test('withShuffle toggles the flag without reordering', () {
      final state = QueueState.prepare(
        _tracks(5),
        shuffle: false,
        newId: _ids(),
      );
      final enabled = state.withShuffle(true);
      expect(enabled.shuffle, isTrue);
      expect(
        enabled.entries.map((entry) => entry.track.id),
        state.entries.map((entry) => entry.track.id),
      );
      final disabled = enabled.withShuffle(false);
      expect(disabled.shuffle, isFalse);
      expect(
        disabled.entries.map((entry) => entry.track.id),
        state.entries.map((entry) => entry.track.id),
      );
    });
  });
}

String Function() _ids([String prefix = 'id-']) {
  var counter = 0;
  return () => '$prefix${counter++}';
}

Track _track(String id) => Track(
  id: id,
  name: 'Song $id',
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
);

List<Track> _tracks(int count) => [
  for (var index = 0; index < count; index++) _track('$index'),
];
