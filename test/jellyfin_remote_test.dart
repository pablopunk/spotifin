import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spotifin/services/jellyfin/jellyfin_client.dart';
import 'package:spotifin/services/jellyfin/remote_session.dart';
import 'package:spotifin/services/jellyfin/session.dart';

void main() {
  test('parses and filters controllable Spotifin sessions', () async {
    final client = JellyfinClient(
      httpClient: MockClient((request) async {
        expect(request.url.path, '/jellyfin/Sessions');
        expect(request.url.queryParameters['controllableByUserId'], 'user');
        return http.Response(
          jsonEncode([
            _sessionJson(),
            _sessionJson(id: 'local', deviceId: 'local-device'),
            _sessionJson(id: 'other-client', client: 'Jellyfin Web'),
            _sessionJson(id: 'other-user', userId: 'someone-else'),
          ]),
          200,
        );
      }),
    );

    final sessions = await client.fetchSessions(_session);

    expect(sessions.map((item) => item.id), ['remote']);
    expect(sessions.single.position, const Duration(seconds: 12));
    expect(sessions.single.queue.map((item) => item.playlistItemId), ['one']);
  });

  test('uses Jellyfin remote command contracts', () async {
    final requests = <http.Request>[];
    final client = JellyfinClient(
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('', 204);
      }),
    );

    await client.advertiseRemoteCapabilities(_session);
    await client.sendPlaystateCommand(
      _session,
      'remote',
      'Seek',
      position: const Duration(seconds: 8),
    );
    await client.sendGeneralCommand(_session, 'remote', 'SetVolume', {
      'Volume': '75',
    });
    await client.sendPlayCommand(
      _session,
      'remote',
      ['first', 'second'],
      startIndex: 1,
      position: const Duration(seconds: 4),
    );

    expect(requests[0].url.path, '/jellyfin/Sessions/Capabilities/Full');
    expect(jsonDecode(requests[0].body), {
      'PlayableMediaTypes': ['Audio'],
      'SupportedCommands': ['SetVolume', 'SetShuffleQueue', 'SetRepeatMode'],
      'SupportsMediaControl': true,
      'SupportsPersistentIdentifier': true,
    });
    expect(requests[1].url.path, '/jellyfin/Sessions/remote/Playing/Seek');
    expect(requests[1].url.queryParameters['seekPositionTicks'], '80000000');
    expect(requests[2].url.path, '/jellyfin/Sessions/remote/Command');
    expect(jsonDecode(requests[2].body), {
      'Name': 'SetVolume',
      'Arguments': {'Volume': '75'},
    });
    expect(requests[3].url.queryParameters, {
      'playCommand': 'PlayNow',
      'itemIds': 'first,second',
      'startIndex': '1',
      'startPositionTicks': '40000000',
    });
  });

  test('builds a secure websocket URI with the server path', () {
    final uri = JellyfinClient().webSocketUri(_session);

    expect(uri.scheme, 'wss');
    expect(uri.host, 'example.com');
    expect(uri.path, '/jellyfin/socket');
    expect(uri.queryParameters, {'ApiKey': 'token'});
  });

  test('reports queue identity and complete playback state', () async {
    late http.Request request;
    final client = JellyfinClient(
      httpClient: MockClient((incoming) async {
        request = incoming;
        return http.Response('', 204);
      }),
    );

    await client.reportPlayback(
      _session,
      '/Sessions/Playing/Progress',
      'song',
      const Duration(seconds: 12),
      playSessionId: 'play',
      playlistItemId: 'second',
      queue: const [
        {'Id': 'song', 'PlaylistItemId': 'first'},
        {'Id': 'song', 'PlaylistItemId': 'second'},
      ],
      volume: 75,
      repeatMode: 'RepeatOne',
      shuffle: true,
    );

    final body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body['PlaylistItemId'], 'second');
    expect(body['NowPlayingQueue'], hasLength(2));
    expect(body['VolumeLevel'], 75);
    expect(body['RepeatMode'], 'RepeatOne');
    expect(body['PlaybackOrder'], 'Shuffle');
  });

  test('parses duplicate queue entries by playlist identity', () {
    final session = RemoteSession.fromJson(
      _sessionJson(
        queue: [
          {'Id': 'song', 'PlaylistItemId': 'first'},
          {'Id': 'song', 'PlaylistItemId': 'second'},
        ],
      ),
    );

    expect(session.queue.map((item) => item.itemId), ['song', 'song']);
    expect(session.queue.map((item) => item.playlistItemId), [
      'first',
      'second',
    ]);
  });
}

Map<String, dynamic> _sessionJson({
  String id = 'remote',
  String userId = 'user',
  String client = 'Spotifin',
  String deviceId = 'remote-device',
  List<Map<String, String>>? queue,
}) => {
  'Id': id,
  'UserId': userId,
  'Client': client,
  'DeviceId': deviceId,
  'DeviceName': 'Spotifin on macOS',
  'SupportsMediaControl': true,
  'IsActive': true,
  'NowPlayingItem': {
    'Id': 'song',
    'Name': 'Song',
    'Artists': ['Artist'],
    'Album': 'Album',
    'PlaylistItemId': 'one',
    'RunTimeTicks': 1800000000,
  },
  'PlayState': {
    'PositionTicks': 120000000,
    'IsPaused': false,
    'CanSeek': true,
    'VolumeLevel': 75,
    'RepeatMode': 'RepeatAll',
    'PlaybackOrder': 'Shuffle',
  },
  'NowPlayingQueue':
      queue ??
      [
        {'Id': 'song', 'PlaylistItemId': 'one'},
      ],
};

const _session = JellyfinSession(
  serverUrl: 'https://example.com/jellyfin',
  serverId: 'server',
  deviceId: 'local-device',
  userId: 'user',
  userName: 'Pablo',
  accessToken: 'token',
);
