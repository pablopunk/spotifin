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
      deviceId: 'spotifin-device',
    );

    expect(session.serverUrl, 'https://example.com/jellyfin');
    expect(session.accessToken, 'token');
    expect(requests.last.headers['Authorization'], contains('MediaBrowser'));
    expect(requests.last.headers['Authorization'], contains('spotifin-device'));
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
        deviceId: 'spotifin-device',
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

  test('reports a rejected authenticated request accurately', () async {
    final client = JellyfinClient(
      httpClient: MockClient((_) async => http.Response('', 401)),
    );
    addTearDown(client.close);
    const session = JellyfinSession(
      serverUrl: 'https://example.com',
      serverId: 'server',
      deviceId: 'spotifin-device',
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
          'Jellyfin did not authorize this request.',
        ),
      ),
    );
  });

  test('sends the dedicated Jellyfin token header', () async {
    late http.Request request;
    final client = JellyfinClient(
      httpClient: MockClient((value) async {
        request = value;
        return http.Response(jsonEncode({'Items': <Object>[]}), 200);
      }),
    );
    addTearDown(client.close);
    const session = JellyfinSession(
      serverUrl: 'https://example.com',
      serverId: 'server',
      deviceId: 'spotifin-device',
      userId: 'user',
      userName: 'Pablo',
      accessToken: 'token',
    );

    await client.fetchTracks(session);

    expect(request.headers['X-Emby-Token'], 'token');
  });

  test('refreshes saved identity from the authenticated user', () async {
    final client = JellyfinClient(
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'Id': 'current-user',
            'Name': 'Current name',
            'ServerId': 'current-server',
          }),
          200,
        ),
      ),
    );
    addTearDown(client.close);
    const session = JellyfinSession(
      serverUrl: 'https://example.com',
      serverId: 'old-server',
      deviceId: 'spotifin-device',
      userId: 'old-user',
      userName: 'Old name',
      accessToken: 'token',
    );

    final refreshed = await client.refreshSession(session);

    expect(refreshed.serverId, 'current-server');
    expect(refreshed.deviceId, 'spotifin-device');
    expect(refreshed.userId, 'current-user');
    expect(refreshed.userName, 'Current name');
    expect(refreshed.accessToken, 'token');
  });

  test('identifies the exact media source in playback URLs', () {
    final client = JellyfinClient();
    addTearDown(client.close);
    const session = JellyfinSession(
      serverUrl: 'https://example.com',
      serverId: 'server',
      deviceId: 'spotifin-device',
      userId: 'user',
      userName: 'Pablo',
      accessToken: 'token',
    );

    final uri = client.streamUri(session, 'track-id');

    expect(uri.path, '/Audio/track-id/stream');
    expect(uri.queryParameters['mediaSourceId'], 'track-id');
    expect(uri.queryParameters['deviceId'], 'spotifin-device');
    expect(uri.queryParameters['static'], 'true');
  });

  test('creates authenticated artwork URLs for system media controls', () {
    final client = JellyfinClient();
    addTearDown(client.close);
    const session = JellyfinSession(
      serverUrl: 'https://example.com',
      serverId: 'server',
      deviceId: 'spotifin-device',
      userId: 'user',
      userName: 'Pablo',
      accessToken: 'token',
    );

    final uri = client.imageUri(session, 'album-id');

    expect(uri.path, '/Items/album-id/Images/Primary');
    expect(uri.queryParameters['api_key'], 'token');
  });

  test('renames a playlist with the playlist update endpoint', () async {
    late http.Request captured;
    final client = JellyfinClient(
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('', 204);
      }),
    );
    addTearDown(client.close);
    const session = JellyfinSession(
      serverUrl: 'https://example.com',
      serverId: 'server',
      deviceId: 'spotifin-device',
      userId: 'user',
      userName: 'Pablo',
      accessToken: 'token',
    );

    await client.renamePlaylist(session, 'playlist-id', 'New name');

    expect(captured.method, 'POST');
    expect(captured.url.path, '/Playlists/playlist-id');
    expect(jsonDecode(captured.body), {'Name': 'New name'});
  });
}
