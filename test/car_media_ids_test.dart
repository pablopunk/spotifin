import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/features/car/car_media_ids.dart';

void main() {
  test('car ids keep a stable kind prefix', () {
    expect(carPlaylistId('abc'), 'car:playlist:abc');
    expect(carArtistId('Miles Davis'), startsWith('car:artist:'));
    expect(carAlbumId('Kind Of Blue'), startsWith('car:album:'));
    expect(carTrackId('track-1'), startsWith('car:track:'));
  });

  test('car ids fall back on empty input', () {
    expect(carPlaylistId(''), 'car:unknown');
    expect(carArtistId(''), 'car:unknown');
    expect(carAlbumId(''), 'car:unknown');
    expect(carTrackId(''), 'car:unknown');
  });

  test('car ids neutralize path traversal', () {
    for (final raw in ['../secret', '/etc/passwd', '%2f..%2f', '..', '.']) {
      expect(carTrackId(raw), startsWith('car:track:'));
      expect(carTrackId(raw), isNot(contains('/')));
    }
  });
}
