import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/services/playback/playback_history.dart';
import 'package:spotifin/storage/database.dart';

void main() {
  test('records most-recent-first and caps at limit', () {
    final history = PlaybackHistory(limit: 3);

    history.record(_track('a'));
    history.record(_track('b'));
    history.record(_track('c'));

    expect(history.items.map((track) => track.id), ['c', 'b', 'a']);

    history.record(_track('d'));

    expect(history.items.map((track) => track.id), ['d', 'c', 'b']);
  });

  test('clear empties history', () {
    final history = PlaybackHistory();
    history.record(_track('a'));

    expect(history.isEmpty, isFalse);

    history.clear();

    expect(history.isEmpty, isTrue);
    expect(history.items, isEmpty);
  });

  test('removeTrack drops every matching entry', () {
    final history = PlaybackHistory();
    history.record(_track('a'));
    history.record(_track('b'));
    history.record(_track('a'));

    history.removeTrack('a');

    expect(history.items.map((track) => track.id), ['b']);
  });

  test('load keeps most-recent-first order and respects limit', () {
    final history = PlaybackHistory(limit: 2);
    history.load([_track('a'), _track('b'), _track('c')]);

    expect(history.items.map((track) => track.id), ['a', 'b']);
    expect(history.toIds(), ['a', 'b']);
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
