import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spotifin/services/jellyfin/jellyfin_client.dart';
import 'package:spotifin/services/jellyfin/session.dart';
import 'package:spotifin/services/mixes/radio_generator.dart';
import 'package:spotifin/services/mixes/radio_service.dart';
import 'package:spotifin/storage/database.dart';

const _session = JellyfinSession(
  serverUrl: 'https://example.com',
  serverId: 'server',
  deviceId: 'spotifin-device',
  userId: 'user',
  userName: 'Pablo',
  accessToken: 'token',
);

void main() {
  group('RadioGenerator', () {
    test('starts with the seed and keeps only related songs', () {
      final seed = _track('seed', 'Artist A', ['Rock']);
      final radio = const RadioGenerator().generate(seed, [
        seed,
        _track('tag', 'Artist B', ['rock']),
        _track('artist', 'Artist A', []),
        _track('unrelated', 'Artist C', ['Jazz']),
      ], random: math.Random(1));

      expect(radio.first.id, 'seed');
      expect(radio.skip(1).map((track) => track.id).toSet(), {'tag', 'artist'});
    });

    test('limits songs from one album and the total length', () {
      final seed = _track('seed', 'Artist A', ['Rock']);
      final catalog = [
        for (var index = 0; index < 10; index++)
          _track('same-$index', 'Artist B', ['Rock'], album: 'One'),
        for (var index = 0; index < 10; index++)
          _track('other-$index', 'Artist B', ['Rock'], album: 'Other $index'),
      ];

      final radio = const RadioGenerator(
        length: 8,
        maxPerAlbum: 2,
      ).generate(seed, catalog, random: math.Random(1));

      expect(radio, hasLength(9));
      expect(radio.where((track) => track.album == 'One').length, 2);
    });

    test('prefers songs that share more tags', () {
      final seed = _track('seed', 'Artist A', ['Rock', 'Indie']);
      final radio = const RadioGenerator(length: 1).generate(seed, [
        _track('one', 'Artist B', ['Rock']),
        _track('two', 'Artist C', ['Rock', 'Indie']),
      ], random: math.Random(1));

      expect(radio.map((track) => track.id), ['seed', 'two']);
    });
  });

  group('RadioService', () {
    late AppDatabase database;
    final seed = _track('seed', 'Artist A', ['Rock']);
    final related = _track('related', 'Artist B', ['Rock']);
    final mixed = _track('mixed', 'Artist C', ['Jazz']);

    setUp(() async {
      database = AppDatabase.forTesting(NativeDatabase.memory());
      await database.upsertTracks([
        for (final track in [seed, related, mixed]) track.toCompanion(true),
      ]);
    });
    tearDown(() => database.close());

    test('uses Jellyfin InstantMix when the server answers', () async {
      final requests = <Uri>[];
      final client = JellyfinClient(
        httpClient: MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            jsonEncode({
              'Items': [
                {'Id': 'seed'},
                {'Id': 'mixed'},
                {'Id': 'not-in-library'},
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(client.close);

      final radio = await RadioService(
        client,
        database,
      ).queueFor(seed, _session);

      expect(requests.single.path, '/Items/seed/InstantMix');
      expect(requests.single.queryParameters['UserId'], 'user');
      expect(radio.map((track) => track.id), ['seed', 'mixed']);
    });

    test('uses the local library when Jellyfin cannot be reached', () async {
      final client = JellyfinClient(
        httpClient: MockClient(
          (_) async => throw http.ClientException('offline'),
        ),
      );
      addTearDown(client.close);

      final radio = await RadioService(
        client,
        database,
      ).queueFor(seed, _session);

      expect(radio.map((track) => track.id), ['seed', 'related']);
    });
  });
}

Track _track(
  String id,
  String artist,
  List<String> labels, {
  String album = 'Album',
}) => Track(
  id: id,
  name: 'Song $id',
  album: album,
  artist: artist,
  artistItems: '[]',
  labels: jsonEncode(labels),
  durationTicks: 10000000,
  favorite: false,
  playCount: 0,
  normalizationGain: null,
  albumNormalizationGain: null,
  container: 'mp3',
);
