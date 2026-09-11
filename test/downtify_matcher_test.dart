import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/services/downtify/downtify_matcher.dart';
import 'package:spotifin/services/downtify/downtify_models.dart';
import 'package:spotifin/storage/database.dart';

void main() {
  const matcher = DowntifyMatcher();

  test('matches punctuation and case without hiding another artist', () {
    final song = DowntifySong.fromJson({
      'song_id': 'external',
      'name': 'One More Time!',
      'artists': ['DAFT PUNK'],
      'duration': 321,
    });
    final tracks = [
      _track('matching', 'One More Time', 'Daft Punk', 321),
      _track('different', 'One More Time', 'Daft Funk', 321),
    ];

    expect(matcher.findMatch(song, tracks)?.id, 'matching');
  });

  test('uses duration to resolve otherwise identical songs', () {
    final song = DowntifySong.fromJson({
      'song_id': 'external',
      'name': 'Song',
      'artists': ['Artist'],
      'duration': 200,
    });
    final tracks = [
      _track('long', 'Song', 'Artist', 400),
      _track('matching', 'Song', 'Artist', 202),
    ];

    expect(matcher.findMatch(song, tracks)?.id, 'matching');
  });
}

Track _track(String id, String name, String artist, int seconds) => Track(
  id: id,
  name: name,
  album: '',
  albumId: null,
  artist: artist,
  artistIds: '[]',
  labels: '[]',
  durationTicks: seconds * 10000000,
  imageTag: null,
  container: 'mp3',
  favorite: false,
  playCount: 0,
  normalizationGain: null,
  albumNormalizationGain: null,
  lastPlayed: null,
  dateCreated: null,
);
