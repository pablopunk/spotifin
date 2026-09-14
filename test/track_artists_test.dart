import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/storage/database.dart';
import 'package:spotifin/storage/track_artists.dart';

void main() {
  test('parses artist items with ids and names', () {
    final track = _track(
      artist: 'Lia Kali, Toni Anzis',
      artistItems:
          '[{"id":"lia","name":"Lia Kali"},{"id":"toni","name":"Toni Anzis"}]',
    );

    expect(track.artistCredits, const [
      TrackArtist(id: 'lia', name: 'Lia Kali'),
      TrackArtist(id: 'toni', name: 'Toni Anzis'),
    ]);
  });

  test('falls back to the artist string when items are empty', () {
    final track = _track(artist: 'Lia Kali, Toni Anzis');

    expect(track.artistCredits, const [
      TrackArtist(name: 'Lia Kali'),
      TrackArtist(name: 'Toni Anzis'),
    ]);
  });

  test('zips legacy id arrays with the artist string', () {
    final track = _track(
      artist: 'Lia Kali, Toni Anzis',
      artistItems: '["lia","toni"]',
    );

    expect(track.artistCredits, const [
      TrackArtist(id: 'lia', name: 'Lia Kali'),
      TrackArtist(id: 'toni', name: 'Toni Anzis'),
    ]);
  });

  test('drops malformed artist items', () {
    final track = _track(artist: 'Lia Kali', artistItems: 'not json');

    expect(track.artistCredits, const [TrackArtist(name: 'Lia Kali')]);
  });

  test('includesArtist matches by id when both sides have one', () {
    final track = _track(
      artist: 'Lia Kali',
      artistItems: '[{"id":"lia","name":"Lia Kali"}]',
    );

    expect(
      includesArtist(track, const TrackArtist(id: 'lia', name: 'Lia Kali')),
      isTrue,
    );
    expect(
      includesArtist(track, const TrackArtist(id: 'other', name: 'Lia Kali')),
      isFalse,
    );
    expect(includesArtist(track, const TrackArtist(name: 'Lia Kali')), isTrue);
  });

  test('encodeArtistItems round trips through parseArtistItems', () {
    const artists = [
      TrackArtist(id: 'lia', name: 'Lia Kali'),
      TrackArtist(name: 'Unknown artist'),
    ];

    expect(parseArtistItems(encodeArtistItems(artists), ''), artists);
  });
}

Track _track({String artist = 'Artist', String artistItems = '[]'}) => Track(
  id: 'track',
  name: 'Song',
  album: '',
  artist: artist,
  artistItems: artistItems,
  labels: '[]',
  durationTicks: 0,
  favorite: false,
  playCount: 0,
  normalizationGain: null,
  albumNormalizationGain: null,
  container: 'mp3',
);
