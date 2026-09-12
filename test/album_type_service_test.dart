import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spotifin/services/albums/album_type_service.dart';
import 'package:spotifin/services/jellyfin/jellyfin_client.dart';
import 'package:spotifin/services/jellyfin/session.dart';
import 'package:spotifin/storage/database.dart';

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => database.close());

  test('resolves release kinds from Jellyfin and MusicBrainz', () async {
    final requests = <Uri>[];
    final service = AlbumTypeService(
      JellyfinClient(httpClient: MockClient(_jellyfinHandler(requests))),
      database,
      httpClient: MockClient(_musicBrainzHandler(requests)),
    );

    final kinds = await service.resolve(_session, [
      'album-ep',
      'album-single',
      'album-plain',
    ]);

    expect(kinds, {'album-ep': AlbumKind.ep, 'album-single': AlbumKind.single});
    expect(await database.albumKindsFor(['album-ep', 'album-single']), {
      'album-ep': 'ep',
      'album-single': 'single',
    });
    expect(
      requests.where((uri) => uri.host == 'musicbrainz.org').single.query,
      contains('rgid:release-ep'),
    );
  });

  test('serves cached kinds without touching the network', () async {
    await database.saveAlbumKinds({'album-ep': 'ep', 'album-plain': ''});
    final requests = <Uri>[];
    final service = AlbumTypeService(
      JellyfinClient(httpClient: MockClient(_jellyfinHandler(requests))),
      database,
      httpClient: MockClient(_musicBrainzHandler(requests)),
    );

    final kinds = await service.resolve(_session, ['album-ep', 'album-plain']);

    expect(kinds, {'album-ep': AlbumKind.ep});
    expect(requests, isEmpty);
  });

  test('falls back to the cache when Jellyfin fails', () async {
    await database.saveAlbumKinds({'album-single': 'single'});
    final service = AlbumTypeService(
      JellyfinClient(
        httpClient: MockClient((request) async {
          throw http.ClientException('offline', request.url);
        }),
      ),
      database,
      httpClient: MockClient((request) async => http.Response('', 500)),
    );

    final kinds = await service.resolve(_session, ['album-single', 'album-ep']);

    expect(kinds, {'album-single': AlbumKind.single});
  });

  test('does not fetch without a session', () async {
    final requests = <Uri>[];
    final service = AlbumTypeService(
      JellyfinClient(httpClient: MockClient(_jellyfinHandler(requests))),
      database,
      httpClient: MockClient(_musicBrainzHandler(requests)),
    );

    expect(await service.resolve(null, ['album-ep']), isEmpty);
    expect(requests, isEmpty);
  });
}

MockClientHandler _jellyfinHandler(List<Uri> requests) => (request) async {
  requests.add(request.url);
  return http.Response(
    jsonEncode({
      'Items': [
        {
          'Id': 'album-ep',
          'ProviderIds': {'MusicBrainzReleaseGroup': 'release-ep'},
        },
        {
          'Id': 'album-single',
          'ProviderIds': {'MusicBrainzReleaseGroup': 'release-single'},
        },
        {'Id': 'album-plain', 'ProviderIds': <String, String>{}},
      ],
    }),
    200,
  );
};

MockClientHandler _musicBrainzHandler(List<Uri> requests) => (request) async {
  requests.add(request.url);
  return http.Response(
    jsonEncode({
      'release-groups': [
        {'id': 'release-ep', 'primary-type': 'EP'},
        {'id': 'release-single', 'primary-type': 'Single'},
        {'id': 'release-album', 'primary-type': 'Album'},
      ],
    }),
    200,
  );
};

const _session = JellyfinSession(
  serverUrl: 'https://jellyfin.test',
  serverId: 'server',
  deviceId: 'device',
  userId: 'user',
  userName: 'Pablo',
  accessToken: 'token',
);
