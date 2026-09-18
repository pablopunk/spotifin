import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/features/coverflow/coverflow_model.dart';
import 'package:spotifin/storage/database.dart';

Track _track({
  required String id,
  required String name,
  String album = '',
  String? albumId,
  String artist = '',
  String artistItems = '[]',
}) => Track(
  id: id,
  name: name,
  album: album,
  albumId: albumId,
  artist: artist,
  artistItems: artistItems,
  labels: '',
  durationTicks: 0,
  container: '',
  favorite: false,
  playCount: 0,
);

void main() {
  test('track items keep one entry per track', () {
    final tracks = [
      _track(id: '1', name: 'One', album: 'A', albumId: 'a', artist: 'X'),
      _track(id: '2', name: 'Two', album: 'A', albumId: 'a', artist: 'X'),
    ];
    final items = trackCoverflowItems(tracks);
    expect(items.length, 2);
    expect(items.first.artItemId, 'a');
    expect(items.first.tracks.single.id, '1');
    expect(items.first.collection, isFalse);
  });

  test('album items group by albumId not name', () {
    final tracks = [
      _track(id: '1', name: 'One', album: 'Hits', albumId: 'a1'),
      _track(id: '2', name: 'Two', album: 'Hits', albumId: 'a2'),
      _track(id: '3', name: 'Three', album: '', albumId: null),
    ];
    final items = albumCoverflowItems(tracks);
    expect(items.length, 2);
    expect(items.map((item) => item.title), contains('Hits'));
    expect(items.every((item) => item.collection), isTrue);
  });

  test('artist items split multi-artist tracks', () {
    final tracks = [
      _track(
        id: '1',
        name: 'Duet',
        album: 'A',
        albumId: 'a',
        artist: 'X, Y',
        artistItems: '[{"id":"x","name":"X"},{"id":"y","name":"Y"}]',
      ),
    ];
    final items = artistCoverflowItems(tracks);
    expect(items.length, 2);
    expect(items.map((item) => item.title), containsAll(['X', 'Y']));
    expect(items.every((item) => item.collection), isTrue);
  });

  test('empty input gives empty output', () {
    expect(trackCoverflowItems(const []), isEmpty);
    expect(albumCoverflowItems(const []), isEmpty);
    expect(artistCoverflowItems(const []), isEmpty);
  });
}
