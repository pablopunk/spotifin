import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/services/playback/mobile_queue.dart';
import 'package:spotifin/services/playback/playback_history.dart';
import 'package:spotifin/storage/database.dart';

void main() {
  group('mobile upcoming view', () {
    test('empty queue stays empty', () {
      expect(MobileQueueView.upcoming(const <String>[], 0), isEmpty);
      expect(MobileQueueView.upcoming(const <String>[], null), isEmpty);
    });

    test('current track is always first', () {
      const queue = ['a', 'b', 'c', 'd'];

      expect(MobileQueueView.upcoming(queue, 0), ['a', 'b', 'c', 'd']);
      expect(MobileQueueView.upcoming(queue, 1), ['b', 'c', 'd']);
      expect(MobileQueueView.upcoming(queue, 2), ['c', 'd']);
      expect(MobileQueueView.upcoming(queue, 3), ['d']);
    });

    test('advancing removes the played track and keeps order', () {
      const queue = ['a', 'b', 'c', 'd'];

      var current = 0;
      expect(MobileQueueView.upcoming(queue, current).first, 'a');

      current = 1;
      final afterNext = MobileQueueView.upcoming(queue, current);
      expect(afterNext.first, 'b');
      expect(afterNext, ['b', 'c', 'd']);
      expect(afterNext.contains('a'), isFalse);

      current = 2;
      expect(MobileQueueView.upcoming(queue, current), ['c', 'd']);
    });

    test('single track shows just the current track', () {
      expect(MobileQueueView.upcoming(const ['only'], 0), ['only']);
    });

    test('exhaustion at the last track shows only the current track', () {
      const queue = ['a', 'b', 'c'];
      expect(MobileQueueView.upcoming(queue, 2), ['c']);
    });

    test('missing or out-of-range index falls back to the full queue', () {
      const queue = ['a', 'b'];
      expect(MobileQueueView.upcoming(queue, null), ['a', 'b']);
      expect(MobileQueueView.upcoming(queue, -1), ['a', 'b']);
      expect(MobileQueueView.upcoming(queue, 7), ['a', 'b']);
    });

    test('mobile to full index translation follows the current offset', () {
      // Queue [a, b, c, d], current b (1): mobile 0 -> full 1.
      expect(MobileQueueView.toFullIndex(0, 1, 4), 1);
      expect(MobileQueueView.toFullIndex(1, 1, 4), 2);
      expect(MobileQueueView.toFullIndex(2, 1, 4), 3);
      expect(MobileQueueView.toFullIndex(3, 1, 4), -1);
      expect(MobileQueueView.toFullIndex(-1, 1, 4), -1);
      expect(MobileQueueView.toFullIndex(0, null, 4), 0);
    });

    test('full to mobile index hides played entries', () {
      expect(MobileQueueView.toMobileIndex(0, 1, 4), -1);
      expect(MobileQueueView.toMobileIndex(1, 1, 4), 0);
      expect(MobileQueueView.toMobileIndex(3, 1, 4), 2);
      expect(MobileQueueView.toMobileIndex(4, 1, 4), -1);
    });

    test('reorder keeps current pinned at mobile 0', () {
      expect(MobileQueueView.reorderFullIndices(0, 2, 1, 4), isNull);
      expect(MobileQueueView.reorderFullIndices(2, 0, 1, 4), isNull);
      expect(MobileQueueView.reorderFullIndices(1, 2, 1, 4), (2, 3));
      expect(MobileQueueView.reorderFullIndices(1, 9, 1, 4), isNull);
      expect(MobileQueueView.reorderFullIndices(-1, 2, 1, 4), isNull);
    });
  });

  group('history back-navigation', () {
    test('forward records, back unwinds without duplication', () {
      final history = PlaybackHistory();
      final a = _track('a');
      final b = _track('b');

      // Play a -> b -> c: record a, then b.
      history.record(a);
      history.record(b);
      expect(history.items.map((t) => t.id), ['b', 'a']);

      // Back from c to b: b becomes current, unwind it from history.
      expect(history.containsId('b'), isTrue);
      history.removeUpToId('b');
      expect(history.items.map((t) => t.id), ['a']);

      // Back from b to a: unwind a, history empties.
      history.removeUpToId('a');
      expect(history.items, isEmpty);
    });

    test('going back does not duplicate upcoming entries', () {
      const queue = ['a', 'b', 'c'];
      final history = PlaybackHistory()
        ..record(_track('a'))
        ..record(_track('b'));

      // Back to b: upcoming is [b, c], history drops b.
      var current = 1;
      history.removeUpToId('b');
      var upcoming = MobileQueueView.upcoming(queue, current);
      expect(upcoming, ['b', 'c']);
      expect(history.items.map((t) => t.id), ['a']);

      // Forward to c again: record b, upcoming is [c].
      history.record(_track('b'));
      current = 2;
      upcoming = MobileQueueView.upcoming(queue, current);
      expect(upcoming, ['c']);
      expect(history.items.map((t) => t.id), ['b', 'a']);
      // Current/upcoming and history share no upcoming entry.
      expect(upcoming.any((id) => history.containsId(id)), isFalse);
    });

    test('direct jump back over skipped tracks unwinds all of them', () {
      final history = PlaybackHistory()
        ..record(_track('a'))
        ..record(_track('b'));
      // Jump from c straight to a: both b and a become current/upcoming.
      history.removeUpToId('a');
      expect(history.items, isEmpty);
    });

    test('playing a history entry removes it through the tapped position', () {
      final history = PlaybackHistory()
        ..record(_track('a'))
        ..record(_track('b'))
        ..record(_track('c'));
      expect(history.items.map((t) => t.id), ['c', 'b', 'a']);

      history.removeThrough(1);
      expect(history.items.map((t) => t.id), ['a']);
    });

    test('takeFirst pops most-recent-first for Previous', () {
      final history = PlaybackHistory()
        ..record(_track('a'))
        ..record(_track('b'));

      expect(history.takeFirst()?.id, 'b');
      expect(history.items.map((t) => t.id), ['a']);
      expect(history.takeFirst()?.id, 'a');
      expect(history.takeFirst(), isNull);
      expect(history.isEmpty, isTrue);
    });

    test('rapid next/previous sequence stays consistent', () {
      const queue = ['a', 'b', 'c', 'd'];
      final history = PlaybackHistory();
      var current = 0;

      // Rapid next, next: a -> b -> c.
      history.record(_track(queue[current]));
      current = 1;
      history.record(_track(queue[current]));
      current = 2;
      expect(MobileQueueView.upcoming(queue, current), ['c', 'd']);
      expect(history.items.map((t) => t.id), ['b', 'a']);

      // Rapid previous, previous: c -> b -> a.
      history.removeUpToId(queue[1]);
      current = 1;
      expect(MobileQueueView.upcoming(queue, current), ['b', 'c', 'd']);
      history.removeUpToId(queue[0]);
      current = 0;
      expect(MobileQueueView.upcoming(queue, current), ['a', 'b', 'c', 'd']);
      expect(history.items, isEmpty);
    });

    test('queue order is preserved around back and forward', () {
      const queue = ['a', 'b', 'c', 'd'];
      expect(MobileQueueView.upcoming(queue, 0), ['a', 'b', 'c', 'd']);
      expect(MobileQueueView.upcoming(queue, 1), ['b', 'c', 'd']);
      expect(MobileQueueView.upcoming(queue, 0), ['a', 'b', 'c', 'd']);
    });
  });
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
