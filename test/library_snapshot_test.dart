import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spotifin/services/jellyfin/account_scope.dart';
import 'package:spotifin/services/jellyfin/jellyfin_client.dart';
import 'package:spotifin/services/jellyfin/library/jellyfin_library.dart';
import 'package:spotifin/services/jellyfin/session.dart';
import 'package:spotifin/storage/database.dart';

const _session = JellyfinSession(
  serverUrl: 'https://music.example.com',
  serverId: 'server',
  deviceId: 'device',
  userId: 'user',
  userName: 'Pablo',
  accessToken: 'token',
);

TracksCompanion _row(String id, {bool favorite = false, String name = ''}) =>
    TracksCompanion.insert(
      id: id,
      name: name.isEmpty ? 'Song $id' : name,
      favorite: Value(favorite),
    );

PlaylistsCompanion _playlist(
  String id, {
  String name = '',
  List<String> trackIds = const [],
}) => PlaylistsCompanion.insert(
  id: id,
  name: name.isEmpty ? 'Playlist $id' : name,
  trackIds: Value(jsonEncode(trackIds)),
);

Future<Map<String, Track>> _tracksById(AppDatabase database) async => {
  for (final track in await database.allTracks()) track.id: track,
};

Future<Map<String, Playlist>> _playlistsById(AppDatabase database) async => {
  for (final playlist in await database.select(database.playlists).get())
    playlist.id: playlist,
};

void main() {
  group('applyLibraryTracks', () {
    test('server metadata applies while pending favorites win', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.upsertTracks([_row('t', favorite: false)]);
      await database.saveFavoriteEdit('t', true);

      await database.applyLibraryTracks([_row('t', favorite: false)]);

      final rows = await _tracksById(database);
      expect(rows['t']!.favorite, isTrue);
      expect(rows['t']!.name, 'Song t');
      // Repeated application stays idempotent.
      await database.applyLibraryTracks([_row('t', favorite: false)]);
      expect((await _tracksById(database))['t']!.favorite, isTrue);
    });

    test('missing tracks with pending edits are retained', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.upsertTracks([_row('edited'), _row('plain')]);
      await database.saveFavoriteEdit('edited', true);

      await database.applyLibraryTracks([_row('other')]);

      final rows = await _tracksById(database);
      expect(rows.keys, containsAll(['edited', 'other']));
      expect(rows.keys, isNot(contains('plain')));
    });

    test('pending playlist references retain missing tracks', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.upsertTracks([_row('t')]);
      await database.into(database.playlists).insert(_playlist('p'));
      await database.savePlaylistAddition('p', 't');

      await database.applyLibraryTracks(const []);

      expect((await _tracksById(database)).keys, ['t']);
    });

    test('empty snapshots clear only unprotected rows', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.upsertTracks([_row('a'), _row('b')]);

      await database.applyLibraryTracks(const []);

      expect(await _tracksById(database), isEmpty);
    });
  });

  group('applyLibraryPlaylists', () {
    test('metadata updates while optimistic membership is retained', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.upsertTracks([_row('local-only')]);
      await database
          .into(database.playlists)
          .insert(_playlist('p', name: 'Old', trackIds: []));
      await database.savePlaylistAddition('p', 'local-only');

      await database.applyLibraryPlaylists([
        _playlist('p', name: 'New', trackIds: ['server-track']),
      ]);

      final rows = await _playlistsById(database);
      expect(rows['p']!.name, 'New');
      expect(jsonDecode(rows['p']!.trackIds), ['local-only']);
      // Repeated application never appends more optimistic entries.
      await database.applyLibraryPlaylists([
        _playlist('p', name: 'New', trackIds: ['server-track']),
      ]);
      expect(jsonDecode((await _playlistsById(database))['p']!.trackIds), [
        'local-only',
      ]);
    });

    test('absent playlists with pending additions are retained', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database
          .into(database.playlists)
          .insert(_playlist('p', trackIds: ['t']));
      await database.savePlaylistAddition('p', 't');

      await database.applyLibraryPlaylists(const []);

      expect((await _playlistsById(database)).keys, ['p']);
    });

    test('server membership applies exactly, duplicates kept', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database
          .into(database.playlists)
          .insert(_playlist('p', trackIds: ['old']));

      await database.applyLibraryPlaylists([
        _playlist('p', trackIds: ['a', 'a', 'b']),
      ]);

      final rows = await _playlistsById(database);
      expect(jsonDecode(rows['p']!.trackIds), ['a', 'a', 'b']);
    });
  });

  group('applyHistoryTracks', () {
    test('partial upsert protects favorites and never clears', () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.upsertTracks([
        _row('played', favorite: false),
        _row('unplayed', favorite: false),
      ]);
      await database.saveFavoriteEdit('played', true);

      await database.applyHistoryTracks([_row('played', favorite: false)]);

      final rows = await _tracksById(database);
      expect(rows['played']!.favorite, isTrue);
      expect(rows.keys, containsAll(['played', 'unplayed']));

      await database.applyHistoryTracks(const []);
      expect((await _tracksById(database)).keys, hasLength(2));
    });
  });

  group('library lane merge policy', () {
    test('edit during fetch remains visible and pending', () async {
      final gate = Completer<void>();
      final sent = <String>[];
      final client = JellyfinClient(
        httpClient: MockClient((request) async {
          if (request is http.Request) {
            sent.add('${request.method} ${request.url.path}');
          }
          final path = request.url.path;
          final types = request.url.queryParameters['IncludeItemTypes'];
          if (request.method == 'GET' && path.endsWith('/Items')) {
            if (types == 'Playlist' || types == 'MusicAlbum') {
              return http.Response(
                jsonEncode({'Items': [], 'TotalRecordCount': 0}),
                200,
              );
            }
            await gate.future;
            return http.Response(
              jsonEncode({
                'Items': [
                  {'Id': 'server', 'Name': 'Server song'},
                ],
                'TotalRecordCount': 1,
              }),
              200,
            );
          }
          return http.Response('', 204);
        }),
      );
      addTearDown(client.close);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.upsertTracks([_row('local')]);
      final scope = AccountScope();
      addTearDown(scope.dispose);
      final library = JellyfinLibrary(client, database, scope);
      final lease = scope.activate(_session);

      final refreshing = library.refreshTracks(lease);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final editing = library.toggleFavorite(lease, 'local', true);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      gate.complete();
      final result = await refreshing;
      await editing;

      expect(result.isCommitted, isTrue);
      final rows = await _tracksById(database);
      expect(rows['local']!.favorite, isTrue);
      expect(rows.keys, contains('server'));
      expect(await database.hasPendingOperations(), isFalse);
      expect(sent, contains('POST /Users/user/FavoriteItems/local'));
    });

    test('failed delivery with successful fetch preserves the edit', () async {
      final client = JellyfinClient(
        httpClient: MockClient((request) async {
          final path = request.url.path;
          final types = request.url.queryParameters['IncludeItemTypes'];
          if (request.method == 'GET' && path.endsWith('/Items')) {
            if (types == 'Playlist' || types == 'MusicAlbum') {
              return http.Response(
                jsonEncode({'Items': [], 'TotalRecordCount': 0}),
                200,
              );
            }
            return http.Response(
              jsonEncode({
                'Items': [
                  {'Id': 't', 'Name': 'Song t'},
                ],
                'TotalRecordCount': 1,
              }),
              200,
            );
          }
          if (path.contains('/FavoriteItems/')) {
            return http.Response('denied', 500);
          }
          return http.Response('', 204);
        }),
      );
      addTearDown(client.close);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.upsertTracks([_row('t', favorite: false)]);
      await database.saveFavoriteEdit('t', true);
      final scope = AccountScope();
      addTearDown(scope.dispose);
      final library = JellyfinLibrary(client, database, scope);
      final lease = scope.activate(_session);

      final result = await library.refresh(lease);

      expect(result.isCommitted, isTrue);
      expect(result.pendingBlocked, isTrue);
      // The failed delivery did not hide the local edit: the snapshot
      // merged around it and the effective catalog still shows it.
      expect(
        result.catalog.singleWhere((track) => track.id == 't').favorite,
        isTrue,
      );
      expect(await database.hasPendingOperations(), isTrue);
    });

    test('failed playlists keep successful tracks available', () async {
      final client = JellyfinClient(
        httpClient: MockClient((request) async {
          final path = request.url.path;
          final types = request.url.queryParameters['IncludeItemTypes'];
          if (request.method == 'GET' && path.endsWith('/Items')) {
            if (types == 'Playlist') {
              return http.Response('denied', 500);
            }
            if (types == 'MusicAlbum') {
              return http.Response(
                jsonEncode({'Items': [], 'TotalRecordCount': 0}),
                200,
              );
            }
            return http.Response(
              jsonEncode({
                'Items': [
                  {'Id': 't', 'Name': 'Song t'},
                ],
                'TotalRecordCount': 1,
              }),
              200,
            );
          }
          return http.Response('', 204);
        }),
      );
      addTearDown(client.close);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final scope = AccountScope();
      addTearDown(scope.dispose);
      final library = JellyfinLibrary(client, database, scope);
      final lease = scope.activate(_session);

      final result = await library.refresh(lease);

      expect(result.isCommitted, isTrue);
      expect(result.playlistError, isNotNull);
      expect(result.catalog.map((track) => track.id), ['t']);
    });

    test('sign-out before apply leaves stale work unapplied', () async {
      final gate = Completer<void>();
      final client = JellyfinClient(
        httpClient: MockClient((request) async {
          final path = request.url.path;
          final types = request.url.queryParameters['IncludeItemTypes'];
          if (request.method == 'GET' && path.endsWith('/Items')) {
            if (types == 'Playlist' || types == 'MusicAlbum') {
              return http.Response(
                jsonEncode({'Items': [], 'TotalRecordCount': 0}),
                200,
              );
            }
            await gate.future;
            return http.Response(
              jsonEncode({
                'Items': [
                  {'Id': 'new', 'Name': 'New'},
                ],
                'TotalRecordCount': 1,
              }),
              200,
            );
          }
          return http.Response('', 204);
        }),
      );
      addTearDown(client.close);
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      await database.upsertTracks([_row('old')]);
      final scope = AccountScope();
      addTearDown(scope.dispose);
      final library = JellyfinLibrary(client, database, scope);
      final lease = scope.activate(_session);

      final refreshing = library.refresh(lease);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      scope.invalidate();
      gate.complete();
      expect((await refreshing).isStale, isTrue);
      expect((await _tracksById(database)).keys, ['old']);
    });

    test(
      'delivered membership is replaced exactly by the next snapshot',
      () async {
        final sent = <String>[];
        final client = JellyfinClient(
          httpClient: MockClient((request) async {
            if (request is http.Request) {
              sent.add('${request.method} ${request.url.path}');
            }
            final path = request.url.path;
            final types = request.url.queryParameters['IncludeItemTypes'];
            if (path.endsWith('/Items') && path.contains('/Playlists/p')) {
              if (request.method == 'GET') {
                return http.Response(
                  jsonEncode({
                    'Items': [
                      {'Id': 't'},
                    ],
                    'TotalRecordCount': 1,
                  }),
                  200,
                );
              }
              return http.Response('', 204);
            }
            if (request.method == 'GET' && path.endsWith('/Items')) {
              if (types == 'Playlist') {
                return http.Response(
                  jsonEncode({
                    'Items': [
                      {'Id': 'p', 'Name': 'Mix'},
                    ],
                    'TotalRecordCount': 1,
                  }),
                  200,
                );
              }
              if (types == 'MusicAlbum') {
                return http.Response(
                  jsonEncode({'Items': [], 'TotalRecordCount': 0}),
                  200,
                );
              }
              return http.Response(
                jsonEncode({'Items': [], 'TotalRecordCount': 0}),
                200,
              );
            }
            return http.Response('', 204);
          }),
        );
        addTearDown(client.close);
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(database.close);
        await database.upsertTracks([_row('t')]);
        await database
            .into(database.playlists)
            .insert(_playlist('p', trackIds: []));
        final scope = AccountScope();
        addTearDown(scope.dispose);
        final library = JellyfinLibrary(client, database, scope);
        final lease = scope.activate(_session);

        await library.addToPlaylist(lease, 'p', 't');
        expect(sent, contains('POST /Playlists/p/Items'));

        // The server now includes the delivered track: the next snapshot
        // replaces the formerly optimistic membership exactly once.
        final result = await library.refresh(lease);
        expect(result.isCommitted, isTrue);
        final playlists = {
          for (final playlist
              in await database.select(database.playlists).get())
            playlist.id: playlist,
        };
        expect(jsonDecode(playlists['p']!.trackIds), ['t']);
        expect(await database.hasPendingOperations(), isFalse);
      },
    );
  });
}
