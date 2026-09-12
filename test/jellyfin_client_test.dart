import 'dart:async';
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

  test('rejects an insecure Jellyfin address', () async {
    final client = JellyfinClient(
      httpClient: MockClient((_) async => http.Response('', 500)),
    );
    addTearDown(client.close);

    expect(
      () => client.authenticate(
        serverUrl: 'http://example.com',
        username: 'Pablo',
        password: 'secret',
        deviceId: 'spotifin-device',
      ),
      throwsA(isA<JellyfinException>()),
    );
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

  test('reads premiere dates with a production year fallback', () async {
    final client = JellyfinClient(
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'Items': [
              {
                'Id': 'dated',
                'Name': 'Dated song',
                'PremiereDate': '2017-07-21T00:00:00.0000000Z',
              },
              {
                'Id': 'year',
                'Name': 'Year song',
                'PremiereDate': '0001-01-01T00:00:00.0000000Z',
                'ProductionYear': 2023,
              },
              {'Id': 'undated', 'Name': 'Undated song'},
            ],
          }),
          200,
        ),
      ),
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

    final tracks = await client.fetchTracks(session);

    expect(tracks[0].premiereDate.value, DateTime.utc(2017, 7, 21));
    expect(tracks[1].premiereDate.value, DateTime(2023));
    expect(tracks[2].premiereDate.value, isNull);
  });

  test('maps album dates with a production year fallback', () async {
    final client = JellyfinClient(
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'Items': [
              {
                'Id': 'album-dated',
                'PremiereDate': '2017-07-21T00:00:00.0000000Z',
              },
              {
                'Id': 'album-year',
                'PremiereDate': '0001-01-01T00:00:00.0000000Z',
                'ProductionYear': 2023,
              },
              {'Id': 'album-undated'},
            ],
          }),
          200,
        ),
      ),
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

    final dates = await client.fetchAlbumDates(session);

    expect(dates, hasLength(2));
    expect(dates.first.albumId.value, 'album-dated');
    expect(dates.first.premiereDate.value, DateTime.utc(2017, 7, 21));
    expect(dates.last.albumId.value, 'album-year');
    expect(dates.last.premiereDate.value, DateTime(2023));
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

  test('starts an authenticated Jellyfin library refresh', () async {
    late http.Request request;
    final client = JellyfinClient(
      httpClient: MockClient((incoming) async {
        request = incoming;
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

    await client.requestLibraryRefresh(session);

    expect(request.method, 'POST');
    expect(request.url.path, '/Library/Refresh');
    expect(request.headers['X-Emby-Token'], 'token');
  });

  test('permanently deletes an authenticated Jellyfin item', () async {
    late http.Request request;
    final client = JellyfinClient(
      httpClient: MockClient((incoming) async {
        request = incoming;
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

    await client.deleteItem(session, 'track-id');

    expect(request.method, 'DELETE');
    expect(request.url.path, '/Items/track-id');
    expect(request.headers['X-Emby-Token'], 'token');
  });

  test('fetches playlist contents with bounded concurrency', () async {
    var inFlight = 0;
    var maxInFlight = 0;
    final client = JellyfinClient(
      httpClient: MockClient((request) async {
        if (request.url.path == '/Users/user/Items') {
          return http.Response(
            jsonEncode({
              'Items': [
                {'Id': 'p1', 'Name': 'One'},
                {'Id': 'p2', 'Name': 'Two'},
                {'Id': 'p3', 'Name': 'Three'},
                {'Id': 'p4', 'Name': 'Four'},
                {'Id': 'p5', 'Name': 'Five'},
              ],
            }),
            200,
          );
        }
        inFlight++;
        if (inFlight > maxInFlight) maxInFlight = inFlight;
        final id = request.url.pathSegments[1];
        await Future<void>.delayed(const Duration(milliseconds: 20));
        inFlight--;
        return http.Response(
          jsonEncode({
            'Items': [
              {'Id': '$id-track'},
            ],
          }),
          200,
        );
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

    final playlists = await client.fetchPlaylists(session);

    expect(maxInFlight, lessThanOrEqualTo(4));
    expect(playlists.map((playlist) => playlist.id.value).toList(), [
      'p1',
      'p2',
      'p3',
      'p4',
      'p5',
    ]);
    expect(jsonDecode(playlists.first.trackIds.value), ['p1-track']);
  });

  test('times out when the response body stalls', () async {
    final client = JellyfinClient(
      httpClient: _StallingClient(),
      requestTimeout: const Duration(milliseconds: 100),
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

    await expectLater(
      client.fetchSessions(session),
      throwsA(isA<TimeoutException>()),
    );
  });
}

class _StallingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(StreamController<List<int>>().stream, 200);
  }
}
