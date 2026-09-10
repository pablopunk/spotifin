import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spotifin/services/jellyfin/jellyfin_client.dart';
import 'package:spotifin/services/jellyfin/session.dart';

void main() {
  test('normalizes a server URL and authenticates', () async {
    final requests = <http.Request>[];
    final client = JellyfinClient(
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/System/Info/Public')) {
          return http.Response(jsonEncode({'Id': 'server'}), 200);
        }
        return http.Response(
          jsonEncode({
            'AccessToken': 'token',
            'User': {'Id': 'user', 'Name': 'Pablo'},
          }),
          200,
        );
      }),
    );

    final session = await client.authenticate(
      serverUrl: 'example.com/jellyfin/',
      username: 'Pablo',
      password: 'secret',
    );

    expect(session.serverUrl, 'https://example.com/jellyfin');
    expect(session.accessToken, 'token');
    expect(requests.last.headers['Authorization'], contains('MediaBrowser'));
  });

  test('reports an authentication failure without exposing a body', () async {
    final client = JellyfinClient(
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/System/Info/Public')) {
          return http.Response('{}', 200);
        }
        return http.Response('sensitive server body', 401);
      }),
    );

    expect(
      () => client.authenticate(
        serverUrl: 'https://example.com',
        username: 'Pablo',
        password: 'secret',
      ),
      throwsA(
        isA<JellyfinException>().having(
          (error) => error.message,
          'message',
          'The username or password is incorrect.',
        ),
      ),
    );
  });

  test('reports an expired authenticated session accurately', () async {
    final client = JellyfinClient(
      httpClient: MockClient((_) async => http.Response('', 401)),
    );
    addTearDown(client.close);
    const session = JellyfinSession(
      serverUrl: 'https://example.com',
      serverId: 'server',
      userId: 'user',
      userName: 'Pablo',
      accessToken: 'expired',
    );

    expect(
      () => client.fetchTracks(session),
      throwsA(
        isA<JellyfinException>().having(
          (error) => error.message,
          'message',
          'The Jellyfin session expired. Sign in again.',
        ),
      ),
    );
  });

  test('identifies the exact media source in playback URLs', () {
    final client = JellyfinClient();
    addTearDown(client.close);
    const session = JellyfinSession(
      serverUrl: 'https://example.com',
      serverId: 'server',
      userId: 'user',
      userName: 'Pablo',
      accessToken: 'token',
    );

    final uri = client.streamUri(session, 'track-id');

    expect(uri.path, '/Audio/track-id/stream');
    expect(uri.queryParameters['mediaSourceId'], 'track-id');
    expect(uri.queryParameters['deviceId'], 'spotifin-server');
    expect(uri.queryParameters['static'], 'true');
  });
}
