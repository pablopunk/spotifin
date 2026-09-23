import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spotifin/services/jellyfin/jellyfin_client.dart';
import 'package:spotifin/services/jellyfin/session.dart';
import 'package:spotifin/services/playback/recently_played.dart';
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
  group('fetchRecentlyPlayed (Jellyfin source of truth)', () {
    test('queries played audio ordered by date played descending', () async {
      late http.Request captured;
      final client = JellyfinClient(
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'Items': [
                {
                  'Id': 'new',
                  'Name': 'New',
                  'UserData': {'LastPlayedDate': '2026-09-20T00:00:00.000Z'},
                },
                {
                  'Id': 'old',
                  'Name': 'Old',
                  'UserData': {'LastPlayedDate': '2026-09-19T00:00:00.000Z'},
                },
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(client.close);

      final rows = await client.fetchRecentlyPlayed(_session, limit: 50);

      final query = captured.url.queryParameters;
      expect(captured.url.path, '/Users/user/Items');
      expect(query['IncludeItemTypes'], 'Audio');
      expect(query['Recursive'], 'true');
      expect(query['Filters'], 'IsPlayed');
      expect(query['SortBy'], 'DatePlayed');
      expect(query['SortOrder'], 'Descending');
      expect(query['Limit'], '50');
      expect(query['EnableUserData'], 'true');
      // Server order is preserved; mapping reuses the track mapping.
      expect(rows.map((row) => row.id.value), ['new', 'old']);
      expect(rows.first.name.value, 'New');
      expect(rows.first.lastPlayed.value, DateTime.utc(2026, 9, 20));
    });

    test('returns an empty list when Jellyfin has no played audio', () async {
      final client = JellyfinClient(
        httpClient: MockClient(
          (_) async => http.Response(jsonEncode({'Items': []}), 200),
        ),
      );
      addTearDown(client.close);

      expect(await client.fetchRecentlyPlayed(_session), isEmpty);
    });
  });

  group('watchRecentlyPlayed (cached Jellyfin truth)', () {
    late AppDatabase database;

    setUp(() => database = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => database.close());

    test('excludes never-played tracks and orders most-recent-first', () async {
      await database.upsertTracks([
        TracksCompanion.insert(
          id: 'old',
          name: 'Old',
          lastPlayed: Value(DateTime.utc(2026, 9, 19)),
        ),
        TracksCompanion.insert(id: 'never', name: 'Never'),
        TracksCompanion.insert(
          id: 'new',
          name: 'New',
          lastPlayed: Value(DateTime.utc(2026, 9, 20)),
        ),
      ]);

      expect((await database.recentlyPlayed()).map((track) => track.id), [
        'new',
        'old',
      ]);
      expect(
        (await database.watchRecentlyPlayed().first).map((track) => track.id),
        ['new', 'old'],
      );
    });

    test('respects the limit', () async {
      await database.upsertTracks([
        for (var index = 0; index < 5; index++)
          TracksCompanion.insert(
            id: 'track-$index',
            name: 'Track $index',
            lastPlayed: Value(DateTime.utc(2026, 9, index + 1)),
          ),
      ]);

      expect((await database.recentlyPlayed(limit: 2)).map((t) => t.id), [
        'track-4',
        'track-3',
      ]);
    });
  });

  group('mergeRecentlyPlayed (presentation-only merge + fallback)', () {
    test('puts session plays first and dedupes by id', () {
      final merged = mergeRecentlyPlayed(
        serverTracks: [_track('a'), _track('b')],
        sessionTracks: [_track('c'), _track('a')],
      );

      // Session copy of 'a' wins; server order of the rest is preserved.
      expect(merged.map((track) => track.id), ['c', 'a', 'b']);
    });

    test('falls back to the session overlay when the server list is empty', () {
      final merged = mergeRecentlyPlayed(
        serverTracks: const [],
        sessionTracks: [_track('c')],
      );

      expect(merged.map((track) => track.id), ['c']);
    });

    test('is empty only when both sources are empty', () {
      expect(
        mergeRecentlyPlayed(serverTracks: const [], sessionTracks: const []),
        isEmpty,
      );
    });

    test('caps the merged list at the limit', () {
      final merged = mergeRecentlyPlayed(
        serverTracks: [_track('b')],
        sessionTracks: [_track('a')],
        limit: 1,
      );

      expect(merged.map((track) => track.id), ['a']);
    });
  });
}

Track _track(String id) => Track(
  id: id,
  name: 'Song $id',
  album: 'Album',
  artist: 'Artist',
  artistItems: '[]',
  labels: '[]',
  durationTicks: 10000000,
  favorite: false,
  playCount: 0,
  normalizationGain: null,
  albumNormalizationGain: null,
  container: 'mp3',
);
