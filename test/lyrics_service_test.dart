import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spotifin/services/jellyfin/jellyfin_client.dart';
import 'package:spotifin/services/jellyfin/session.dart';
import 'package:spotifin/services/lyrics/lyrics_service.dart';
import 'package:spotifin/storage/database.dart';

void main() {
  test('uses the browser-safe LRCLIB client header', () async {
    late http.Request lrclibRequest;
    final jellyfin = JellyfinClient(
      httpClient: MockClient((_) async => http.Response('', 204)),
    );
    final service = LyricsService(
      jellyfin,
      httpClient: MockClient((request) async {
        lrclibRequest = request;
        return http.Response(jsonEncode({'plainLyrics': 'A lyric'}), 200);
      }),
    );

    final lyrics = await service.find(_session, _track);

    expect(lyrics.single.text, 'A lyric');
    expect(lrclibRequest.headers['Lrclib-Client'], 'Spotifin/1.0');
    expect(lrclibRequest.headers, isNot(contains('User-Agent')));
  });

  test('rewrites "you" to "u" when the exact match misses', () async {
    final requests = <Uri>[];
    final service = LyricsService(
      _jellyfinClient(),
      httpClient: MockClient((request) async {
        requests.add(request.url);
        if (request.url.path == '/api/get') return http.Response('', 404);
        if (request.url.queryParameters['track_name'] ==
            'I Know What U Did Last Summer') {
          return http.Response(jsonEncode([_record()]), 200);
        }
        return http.Response('[]', 200);
      }),
    );

    final lyrics = await service.find(_session, _zebraheadTrack);

    expect(lyrics.single.text, 'Where was I');
    expect(requests.first.path, '/api/get');
    expect(requests[1].path, '/api/search');
    expect(
      requests[1].queryParameters['track_name'],
      'I Know What You Did Last Summer',
    );
    expect(
      requests.last.queryParameters['track_name'],
      'I Know What U Did Last Summer',
    );
  });

  test('picks the search result closest in duration', () async {
    final service = LyricsService(
      _jellyfinClient(),
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/get') return http.Response('', 404);
        return http.Response(
          jsonEncode([
            _record(duration: 60, synced: '[00:01.00]Wrong', plain: 'Wrong'),
            _record(duration: 164, synced: '[00:01.00]Right', plain: 'Right'),
          ]),
          200,
        );
      }),
    );

    final lyrics = await service.find(_session, _zebraheadTrack);

    expect(lyrics.single.text, 'Right');
  });

  test('rejects search results with unrelated titles', () async {
    final service = LyricsService(
      _jellyfinClient(),
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/get') return http.Response('', 404);
        return http.Response(jsonEncode([_record(name: 'Another Song')]), 200);
      }),
    );

    expect(await service.find(_session, _zebraheadTrack), isEmpty);
  });

  test('skips instrumental search results', () async {
    final service = LyricsService(
      _jellyfinClient(),
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/get') return http.Response('', 404);
        return http.Response(jsonEncode([_record(instrumental: true)]), 200);
      }),
    );

    expect(await service.find(_session, _zebraheadTrack), isEmpty);
  });
}

JellyfinClient _jellyfinClient() =>
    JellyfinClient(httpClient: MockClient((_) async => http.Response('', 204)));

Map<String, dynamic> _record({
  String name = 'I Know What U Did Last Summer',
  String artist = 'zebrahead',
  double duration = 165,
  bool instrumental = false,
  String? synced = '[00:09.74]Where was I',
  String? plain = 'Where was I',
}) => {
  'trackName': name,
  'artistName': artist,
  'duration': duration,
  'instrumental': instrumental,
  'syncedLyrics': ?synced,
  'plainLyrics': ?plain,
};

const _zebraheadTrack = Track(
  id: 'zebrahead-track',
  name: 'I Know What You Did Last Summer',
  album: 'O',
  albumId: null,
  artist: 'zebrahead',
  artistIds: '[]',
  labels: '[]',
  durationTicks: 1650000000,
  imageTag: null,
  container: 'mp3',
  favorite: false,
  playCount: 0,
  normalizationGain: null,
  albumNormalizationGain: null,
  lastPlayed: null,
  dateCreated: null,
);

const _session = JellyfinSession(
  serverUrl: 'https://jellyfin.example.com',
  serverId: 'server',
  deviceId: 'device',
  userId: 'user',
  userName: 'Pablo',
  accessToken: 'token',
);

const _track = Track(
  id: 'track',
  name: 'Song',
  album: 'Album',
  albumId: null,
  artist: 'Artist',
  artistIds: '[]',
  labels: '[]',
  durationTicks: 1800000000,
  imageTag: null,
  container: 'mp3',
  favorite: false,
  playCount: 0,
  normalizationGain: null,
  albumNormalizationGain: null,
  lastPlayed: null,
  dateCreated: null,
);
