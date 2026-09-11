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
}

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
