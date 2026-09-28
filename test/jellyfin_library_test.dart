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

class _LibraryHarness {
  _LibraryHarness({
    required this.tracks,
    this.playlists = const [],
    this.history = const [],
    this.tracksStatus = 200,
  }) : sent = [] {
    client = JellyfinClient(
      httpClient: MockClient((request) async {
        sent.add('${request.method} ${request.url.path}');
        final path = request.url.path;
        final query = request.url.queryParameters;
        if (request.method == 'GET' && path.endsWith('/Items')) {
          final types = query['IncludeItemTypes'];
          if (types == 'Playlist') {
            return _json({
              'Items': playlists,
              'TotalRecordCount': playlists.length,
            });
          }
          if (types == 'MusicAlbum') {
            return _json({'Items': [], 'TotalRecordCount': 0});
          }
          if (query['Filters'] == 'IsPlayed') {
            return _json({
              'Items': history,
              'TotalRecordCount': history.length,
            });
          }
          if (tracksStatus != 200) {
            return http.Response('server exploded', tracksStatus);
          }
          return _json({'Items': tracks, 'TotalRecordCount': tracks.length});
        }
        if (path.contains('/Playlists/') &&
            path.endsWith('/Items') &&
            request.method == 'GET') {
          return _json({'Items': [], 'TotalRecordCount': 0});
        }
        if (path.contains('/FavoriteItems/')) {
          return http.Response('', 204);
        }
        if (path.contains('/Playlists/') && path.endsWith('/Items')) {
          return http.Response('', 204);
        }
        if (request.method == 'POST' && path.endsWith('/Playlists')) {
          return http.Response('{"Id": "new-playlist"}', 200);
        }
        if (request.method == 'POST' && path.contains('/Playlists/')) {
          return http.Response('', 200);
        }
        if (request.method == 'DELETE') {
          return http.Response('', 204);
        }
        return http.Response('', 204);
      }),
    );
    scope = AccountScope();
    addTearDown(scope.dispose);
    library = JellyfinLibrary(client, database, scope);
  }

  static http.Response _json(Object body) =>
      http.Response(jsonEncode(body), 200);

  late final AppDatabase database = AppDatabase.forTesting(
    NativeDatabase.memory(),
  );
  late final JellyfinClient client;
  late final AccountScope scope;
  late final JellyfinLibrary library;
  final List<Map<String, dynamic>> tracks;
  final List<Map<String, dynamic>> playlists;
  final List<Map<String, dynamic>> history;
  final int tracksStatus;
  final List<String> sent;

  AccountLease activate() => scope.activate(_session);

  Future<void> dispose() async {
    await database.close();
    client.close();
  }

  bool get didFetchTracks => sent.any(
    (call) =>
        call.startsWith('GET') &&
        call.contains('/Items') &&
        !call.contains('Playlist'),
  );
}

Map<String, dynamic> _song(String id, {bool favorite = false}) => {
  'Id': id,
  'Name': 'Song $id',
  if (favorite) 'UserData': {'IsFavorite': true},
};

void main() {
  test(
    'refresh commits tracks and playlists and returns the catalog',
    () async {
      final harness = _LibraryHarness(
        tracks: [_song('t1'), _song('t2')],
        playlists: [
          {'Id': 'p1', 'Name': 'Mix'},
        ],
      );
      addTearDown(harness.dispose);
      final lease = harness.activate();

      final result = await harness.library.refresh(lease);

      expect(result.isCommitted, isTrue);
      expect(result.catalog.map((track) => track.id), ['t1', 't2']);
      expect(result.pendingBlocked, isFalse);
      expect(result.playlistError, isNull);
      expect((await harness.database.allTracks()).map((track) => track.id), [
        't1',
        't2',
      ]);
      expect(
        (await harness.database.select(harness.database.playlists).get()).map(
          (playlist) => playlist.id,
        ),
        ['p1'],
      );
    },
  );

  test('refreshTracks reads and commits tracks only', () async {
    final harness = _LibraryHarness(tracks: [_song('t1')]);
    addTearDown(harness.dispose);
    final lease = harness.activate();

    // Constructed directly from client, database, and scope: no playback,
    // download, car, remote, or Cast provider is involved.
    final result = await harness.library.refreshTracks(lease);

    expect(result.isCommitted, isTrue);
    expect(result.catalog.map((track) => track.id), ['t1']);
    expect((await harness.database.allTracks()).map((track) => track.id), [
      't1',
    ]);
  });

  test('failed tracks refresh preserves the underlying error', () async {
    final harness = _LibraryHarness(tracks: const [], tracksStatus: 500);
    addTearDown(harness.dispose);
    await harness.database.upsertTracks([
      TracksCompanion.insert(id: 'kept', name: 'Kept'),
    ]);
    final lease = harness.activate();

    final result = await harness.library.refreshTracks(lease);

    expect(result.isFailed, isTrue);
    expect(result.error, isA<JellyfinException>());
    // Failed results leave existing rows unchanged.
    expect((await harness.database.allTracks()).map((track) => track.id), [
      'kept',
    ]);
  });

  test('stale lease returns stale without network effects', () async {
    final harness = _LibraryHarness(tracks: [_song('t1')]);
    addTearDown(harness.dispose);
    final lease = harness.activate();
    harness.scope.invalidate();

    final result = await harness.library.refresh(lease);

    expect(result.isStale, isTrue);
    expect(harness.sent, isEmpty);
    expect(await harness.database.allTracks(), isEmpty);
  });

  test('toggleFavorite updates locally immediately, then delivers', () async {
    final harness = _LibraryHarness(tracks: [_song('t1')]);
    addTearDown(harness.dispose);
    await harness.database.upsertTracks([
      TracksCompanion.insert(id: 't1', name: 'Song t1'),
    ]);
    final lease = harness.activate();

    await harness.library.toggleFavorite(lease, 't1', true);

    expect(
      (await harness.database.allTracks())
          .singleWhere((track) => track.id == 't1')
          .favorite,
      isTrue,
    );
    expect(harness.sent, contains('POST /Users/user/FavoriteItems/t1'));
    expect(await harness.database.hasPendingOperations(), isFalse);
  });

  test('addToPlaylist appends locally without a playlist refetch', () async {
    final harness = _LibraryHarness(
      tracks: [_song('t1')],
      playlists: [
        {'Id': 'p1', 'Name': 'Mix'},
      ],
    );
    addTearDown(harness.dispose);
    await harness.database.upsertTracks([
      TracksCompanion.insert(id: 't1', name: 'Song t1'),
    ]);
    await harness.database
        .into(harness.database.playlists)
        .insert(
          PlaylistsCompanion.insert(
            id: 'p1',
            name: 'Mix',
            trackIds: const Value('[]'),
          ),
        );
    final lease = harness.activate();

    await harness.library.addToPlaylist(lease, 'p1', 't1');

    final playlist =
        (await harness.database.select(harness.database.playlists).get())
            .single;
    expect(jsonDecode(playlist.trackIds), ['t1']);
    expect(harness.sent, contains('POST /Playlists/p1/Items'));
    // Membership appended locally: no playlist snapshot reread happened.
    expect(
      harness.sent.where((call) => call.startsWith('GET')).toList(),
      isEmpty,
    );
  });

  test('createPlaylist posts then refetches membership', () async {
    final harness = _LibraryHarness(
      tracks: [_song('t1')],
      playlists: [
        {'Id': 'srv-1', 'Name': 'Server Mix'},
      ],
    );
    addTearDown(harness.dispose);
    final lease = harness.activate();

    await harness.library.createPlaylist(lease, 'Fresh', ['t1']);

    expect(harness.sent, contains('POST /Playlists'));
    expect(
      (await harness.database.select(harness.database.playlists).get()).map(
        (playlist) => playlist.id,
      ),
      ['srv-1'],
    );
  });

  test('deleteTrack removes server, local, and pending references', () async {
    final harness = _LibraryHarness(tracks: const []);
    addTearDown(harness.dispose);
    await harness.database.upsertTracks([
      TracksCompanion.insert(id: 't1', name: 'Song t1'),
    ]);
    await harness.database
        .into(harness.database.playlists)
        .insert(
          PlaylistsCompanion.insert(
            id: 'p1',
            name: 'Mix',
            trackIds: const Value('[]'),
          ),
        );
    await harness.database.savePlaylistAddition('p1', 't1');
    final lease = harness.activate();

    await harness.library.deleteTrack(lease, 't1');

    expect(harness.sent, contains('DELETE /Items/t1'));
    expect(await harness.database.allTracks(), isEmpty);
    expect(await harness.database.hasPendingOperations(), isFalse);
  });

  test('history refresh upserts without clearing tracks', () async {
    final harness = _LibraryHarness(
      tracks: [_song('t1'), _song('t2')],
      history: [
        {
          'Id': 't1',
          'Name': 'Song t1',
          'UserData': {'LastPlayedDate': '2026-05-01T00:00:00.000Z'},
        },
      ],
    );
    addTearDown(harness.dispose);
    await harness.database.upsertTracks([
      TracksCompanion.insert(id: 't1', name: 'Song t1'),
      TracksCompanion.insert(id: 't2', name: 'Song t2'),
    ]);
    final lease = harness.activate();

    final result = await harness.library.refreshHistory(lease);

    expect(result.isCommitted, isTrue);
    expect(
      (await harness.database.allTracks()).map((track) => track.id),
      containsAll(['t1', 't2']),
    );

    final empty = _LibraryHarness(tracks: [_song('t1')], history: const []);
    addTearDown(empty.dispose);
    await empty.database.upsertTracks([
      TracksCompanion.insert(id: 't1', name: 'Song t1'),
    ]);
    final emptyLease = empty.scope.activate(_session);
    final emptyResult = await empty.library.refreshHistory(emptyLease);
    expect(emptyResult.isCommitted, isTrue);
    expect((await empty.database.allTracks()).map((track) => track.id), ['t1']);
  });

  test('expired credentials surface the underlying 401', () async {
    final harness = _LibraryHarness(tracks: const [], tracksStatus: 401);
    addTearDown(harness.dispose);
    final lease = harness.activate();

    final result = await harness.library.refreshTracks(lease);

    expect(result.isFailed, isTrue);
    final error = result.error;
    expect(error, isA<JellyfinException>());
    expect((error as JellyfinException).statusCode, 401);
  });
}
