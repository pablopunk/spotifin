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

/// Recorded mutating request.
class _SentRequest {
  _SentRequest(this.method, this.path, this.query, this.body);

  final String method;
  final String path;
  final String query;
  final String body;
}

class _LibraryHarness {
  _LibraryHarness({
    Future<http.Response> Function(http.BaseRequest request)? onRequest,
  }) : sent = [] {
    client = JellyfinClient(
      httpClient: MockClient((request) async {
        if (request is http.Request) {
          sent.add(
            _SentRequest(
              request.method,
              request.url.path,
              request.url.query,
              request.body,
            ),
          );
        }
        final handler = onRequest;
        if (handler != null) return handler(request);
        return http.Response('', 204);
      }),
    );
    scope = AccountScope();
    addTearDown(scope.dispose);
    library = JellyfinLibrary(client, database, scope);
  }

  late final AppDatabase database = AppDatabase.forTesting(
    NativeDatabase.memory(),
  );
  late final JellyfinClient client;
  late final AccountScope scope;
  late final JellyfinLibrary library;
  final List<_SentRequest> sent;

  AccountLease activate() => scope.activate(_session);

  Future<void> dispose() async {
    await database.close();
    client.close();
  }

  List<_SentRequest> postsTo(String suffix) =>
      sent.where((request) => request.path.endsWith(suffix)).toList();
}

Future<void> _seedTrack(AppDatabase database, String id) =>
    database.upsertTracks([TracksCompanion.insert(id: id, name: 'Song $id')]);

Future<void> _seedPlaylist(
  AppDatabase database,
  String id, [
  List<String> trackIds = const [],
]) => database
    .into(database.playlists)
    .insertOnConflictUpdate(
      PlaylistsCompanion.insert(
        id: id,
        name: 'Playlist $id',
        trackIds: Value(jsonEncode(trackIds)),
      ),
    );

void main() {
  test('two concurrent flushes deliver one operation once', () async {
    final gate = Completer<void>();
    final harness = _LibraryHarness(
      onRequest: (request) async {
        await gate.future;
        return http.Response('', 204);
      },
    );
    addTearDown(harness.dispose);
    await _seedTrack(harness.database, 't');
    final lease = harness.activate();
    await harness.database.saveFavoriteEdit('t', false);
    final first = harness.library.requestDrain(lease);
    final second = harness.library.requestDrain(lease);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    gate.complete();
    final results = await Future.wait([first, second]);
    expect(results, [true, false]);

    final favorites = harness.postsTo('/FavoriteItems/t');
    expect(favorites, hasLength(1));
    expect(await harness.database.hasPendingOperations(), isFalse);
  });

  test('equal-time operations keep rowid order with distinct ids', () async {
    final harness = _LibraryHarness();
    addTearDown(harness.dispose);
    final lease = harness.activate();
    final moment = DateTime(2026, 1, 1);
    await harness.database
        .into(harness.database.pendingWrites)
        .insert(
          PendingWritesCompanion.insert(
            id: 'first',
            kind: 'playlistAdd',
            targetId: 'p',
            payload: Value(jsonEncode({'trackId': 'a'})),
            createdAt: moment,
          ),
        );
    await harness.database
        .into(harness.database.pendingWrites)
        .insert(
          PendingWritesCompanion.insert(
            id: 'second',
            kind: 'playlistAdd',
            targetId: 'p',
            payload: Value(jsonEncode({'trackId': 'b'})),
            createdAt: moment,
          ),
        );

    expect(await harness.library.requestDrain(lease), isTrue);
    final posts = harness.postsTo('/Items');
    expect(posts, hasLength(2));
    // Insertion order, not lexical id order.
    expect(posts.map((post) => post.query), [
      contains('ids=a'),
      contains('ids=b'),
    ]);
    expect(await harness.database.hasPendingOperations(), isFalse);
  });

  test('favorite replacement during a request acks only its own id', () async {
    final gate = Completer<void>();
    var posts = 0;
    final harness = _LibraryHarness(
      onRequest: (request) async {
        posts++;
        if (posts == 1) await gate.future;
        return http.Response('', 204);
      },
    );
    addTearDown(harness.dispose);
    await _seedTrack(harness.database, 't');
    final lease = harness.activate();

    await harness.database.saveFavoriteEdit('t', true);
    final draining = harness.library.requestDrain(lease);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    // A newer edit lands while A's request is in flight; it must survive
    // A's acknowledgement and be delivered afterwards with its own id.
    final replacing = harness.library.toggleFavorite(lease, 't', false);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    gate.complete();
    await Future.wait([draining, replacing]);

    final favorites = harness.postsTo('/FavoriteItems/t');
    expect(favorites, hasLength(2));
    expect(await harness.database.hasPendingOperations(), isFalse);
    final rows = await harness.database.allTracks();
    expect(rows.singleWhere((track) => track.id == 't').favorite, isFalse);
  });

  test('removed queued targets are skipped without a request', () async {
    final harness = _LibraryHarness();
    addTearDown(harness.dispose);
    await _seedTrack(harness.database, 't');
    await _seedPlaylist(harness.database, 'p');
    final lease = harness.activate();
    await harness.database.savePlaylistAddition('p', 't');
    await harness.database.removeTrack('t');

    expect(await harness.library.requestDrain(lease), isTrue);
    expect(harness.postsTo('/Items'), isEmpty);
    expect(await harness.database.hasPendingOperations(), isFalse);
  });

  test('unknown kinds stay pending and report blocked', () async {
    final harness = _LibraryHarness();
    addTearDown(harness.dispose);
    final lease = harness.activate();
    await harness.database
        .into(harness.database.pendingWrites)
        .insert(
          PendingWritesCompanion.insert(
            id: 'mystery',
            kind: 'mystery',
            targetId: 't',
            payload: const Value('{}'),
            createdAt: DateTime.now(),
          ),
        );

    expect(await harness.library.requestDrain(lease), isFalse);
    expect(harness.sent, isEmpty);
    final remaining = await harness.database.pendingOperationById('mystery');
    expect(remaining, isNotNull);
  });

  test('old-account acknowledgement is rejected', () async {
    final gate = Completer<void>();
    final harness = _LibraryHarness(
      onRequest: (request) async {
        await gate.future;
        return http.Response('', 204);
      },
    );
    addTearDown(harness.dispose);
    await _seedTrack(harness.database, 't');
    final lease = harness.activate();
    await harness.database.saveFavoriteEdit('t', true);

    final draining = harness.library.requestDrain(lease);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    harness.scope.invalidate();
    gate.complete();
    expect(await draining, isFalse);
    // The late completion must not acknowledge the edit.
    expect(await harness.database.hasPendingOperations(), isTrue);
  });

  test('edit saved during an empty drain is delivered once', () async {
    final harness = _LibraryHarness();
    addTearDown(harness.dispose);
    await _seedTrack(harness.database, 't');
    final lease = harness.activate();

    final first = harness.library.requestDrain(lease);
    await harness.database.saveFavoriteEdit('t', true);
    final second = harness.library.requestDrain(lease);
    await Future.wait([first, second]);
    // Allow a joined follow-up drain to finish the new op.
    await harness.library.requestDrain(lease);

    expect(harness.postsTo('/FavoriteItems/t'), hasLength(1));
    expect(await harness.database.hasPendingOperations(), isFalse);
  });

  test('failed drain followed by refresh recovers without deadlock', () async {
    var failPosts = true;
    final harness = _LibraryHarness(
      onRequest: (request) async {
        final path = request.url.path;
        if (request.method == 'GET' && path.endsWith('/Items')) {
          final types = request.url.queryParameters['IncludeItemTypes'];
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
        if (failPosts) return http.Response('nope', 500);
        return http.Response('', 204);
      },
    );
    addTearDown(harness.dispose);
    await _seedTrack(harness.database, 't');
    final lease = harness.activate();
    await harness.database.saveFavoriteEdit('t', true);

    expect(await harness.library.requestDrain(lease), isFalse);
    final stuck = await harness.database.pendingOperationById(
      (await harness.database.pendingOperations()).single.id,
    );
    expect(stuck, isNotNull);
    expect(stuck!.attempts, 1);

    final blocked = await harness.library.refreshTracks(lease);
    expect(blocked.isCommitted, isTrue);
    expect(blocked.pendingBlocked, isTrue);
    expect(blocked.catalog.map((track) => track.id), ['t']);

    failPosts = false;
    final recovered = await harness.library.refreshTracks(lease);
    expect(recovered.isCommitted, isTrue);
    expect(recovered.pendingBlocked, isFalse);
    expect(await harness.database.hasPendingOperations(), isFalse);
  });

  test('same-instant favorite ids stay distinct', () async {
    final harness = _LibraryHarness();
    addTearDown(harness.dispose);
    await _seedTrack(harness.database, 't');
    final lease = harness.activate();
    await harness.library.toggleFavorite(lease, 't', true);
    await harness.library.toggleFavorite(lease, 't', false);

    // Two rapid edits share a clock timestamp yet keep distinct rows and
    // both are delivered exactly once.
    expect(harness.postsTo('/FavoriteItems/t'), hasLength(2));
    expect(await harness.database.hasPendingOperations(), isFalse);
  });
}
