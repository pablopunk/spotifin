import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/app/state/app_controller.dart';
import 'package:spotifin/features/auth/login_screen.dart';
import 'package:spotifin/services/cast/cast_controller.dart';
import 'package:spotifin/services/downloads/download_service.dart';
import 'package:spotifin/services/jellyfin/account_scope.dart';
import 'package:spotifin/services/jellyfin/jellyfin_client.dart';
import 'package:spotifin/services/jellyfin/library_cache_owner_store.dart';
import 'package:spotifin/services/jellyfin/session.dart';
import 'package:spotifin/services/playback/playback_service.dart';
import 'package:spotifin/services/playback/remote_session_service.dart';
import 'package:spotifin/storage/database.dart';

const _ownerSession = JellyfinSession(
  serverUrl: 'https://music.example.com',
  serverId: 'server',
  deviceId: 'device',
  userId: 'owner',
  userName: 'Owner',
  accessToken: 'owner-token',
);

class _MockPlayback extends Mock implements PlaybackService {}

class _MockDownload extends Mock implements DownloadService {}

class _MockRemote extends Mock implements RemoteSessionService {}

class _MockCast extends Mock implements CastController {}

void _stubMocks(
  _MockPlayback playback,
  _MockDownload downloads,
  _MockRemote remote,
  _MockCast cast,
) {
  when(() => playback.queue).thenReturn([]);
  when(
    () => playback.configure(
      any(),
      smallStreaming: any(named: 'smallStreaming'),
      normalization: any(named: 'normalization'),
    ),
  ).thenAnswer((_) async {});
  when(() => playback.restore(any())).thenAnswer((_) async {});
  when(() => playback.clear()).thenAnswer((_) async {});
  when(() => playback.removeTrack(any())).thenAnswer((_) async {});
  when(() => downloads.reconcile(any())).thenAnswer((_) async {});
  when(() => downloads.resume(any(), any(), small: any(named: 'small')))
      .thenAnswer((_) async {});
  when(() => downloads.remove(any())).thenAnswer((_) async {});
  when(() => downloads.clear()).thenAnswer((_) async {});
  when(() => downloads.suspend()).thenAnswer((_) async {});
  when(() => remote.configure(any())).thenAnswer((_) async {});
  when(() => remote.clear()).thenAnswer((_) async {});
  when(() => cast.configure(any())).thenAnswer((_) async {});
  when(() => cast.disconnect(resumeLocal: any(named: 'resumeLocal')))
      .thenAnswer((_) async {});
}

Future<ProviderContainer> _makeContainer({
  required AppDatabase database,
  required AccountScope scope,
  required JellyfinClient client,
  required _MockPlayback playback,
  required _MockDownload downloads,
  required _MockRemote remote,
  required _MockCast cast,
}) async {
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(database),
      jellyfinClientProvider.overrideWithValue(client),
      accountScopeProvider.overrideWithValue(scope),
      playbackProvider.overrideWithValue(playback),
      downloadProvider.overrideWithValue(downloads),
      remoteSessionProvider.overrideWithValue(remote),
      castControllerProvider.overrideWithValue(cast),
    ],
  );
  return container;
}

JellyfinClient _authClient({
  required String userId,
  required String userName,
  required String token,
  List<http.Request>? sent,
}) => JellyfinClient(
  httpClient: MockClient((request) async {
    sent?.add(request);
    if (request.url.path == '/System/Info/Public') {
      return http.Response('{"Id":"server"}', 200);
    }
    if (request.url.path == '/Users/AuthenticateByName') {
      return http.Response(
        '{"AccessToken":"$token","User":{"Id":"$userId","Name":"$userName"}}',
        200,
      );
    }
    if (request.url.path == '/Users/Me') {
      return http.Response(
        '{"Id":"$userId","Name":"$userName","ServerId":"server"}',
        200,
      );
    }
    if (request.url.path.contains('/Items')) {
      return http.Response('{"Items":[],"TotalRecordCount":0}', 200);
    }
    return http.Response('', 204);
  }),
);

void main() {
  setUpAll(() {
    registerFallbackValue(_ownerSession);
    registerFallbackValue(<Track>[]);
  });

  test('matching account reuses cache without conflict', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.upsertTracks([
      TracksCompanion.insert(id: 't1', name: 'Song'),
    ]);
    await database.saveFavoriteEdit('t1', true);
    final scope = AccountScope();
    final playback = _MockPlayback();
    final downloads = _MockDownload();
    final remote = _MockRemote();
    final cast = _MockCast();
    _stubMocks(playback, downloads, remote, cast);
    final sent = <http.Request>[];
    final client = _authClient(
      userId: 'owner',
      userName: 'Owner',
      token: 'owner-token',
      sent: sent,
    );
    // Pre-assign the marker to the same account.
    await LibraryCacheOwnerStore().saveOwner(_ownerSession);
    final container = await _makeContainer(
      database: database,
      scope: scope,
      client: client,
      playback: playback,
      downloads: downloads,
      remote: remote,
      cast: cast,
    );
    addTearDown(() async {
      container.dispose();
      scope.dispose();
      client.close();
      await database.close();
    });

    final ok = await container
        .read(appControllerProvider.notifier)
        .signIn('https://music.example.com', 'owner', 'password')
        .timeout(const Duration(seconds: 5));

    expect(ok, isTrue);
    expect(container.read(appControllerProvider).cacheOwnerConflict, isFalse);
    expect(container.read(appControllerProvider).status, AppStatus.ready);
  });

  test('mismatched marker blocks the switch and keeps rows', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.upsertTracks([
      TracksCompanion.insert(id: 't1', name: 'Song'),
    ]);
    await database.saveFavoriteEdit('t1', true);
    final pendingBefore = await database.pendingOperations();
    expect(pendingBefore, hasLength(1));
    await LibraryCacheOwnerStore().saveOwner(_ownerSession);
    final scope = AccountScope();
    final playback = _MockPlayback();
    final downloads = _MockDownload();
    final remote = _MockRemote();
    final cast = _MockCast();
    _stubMocks(playback, downloads, remote, cast);
    final sent = <http.Request>[];
    final client = _authClient(
      userId: 'other',
      userName: 'Other',
      token: 'other-token',
      sent: sent,
    );
    final container = await _makeContainer(
      database: database,
      scope: scope,
      client: client,
      playback: playback,
      downloads: downloads,
      remote: remote,
      cast: cast,
    );
    addTearDown(() async {
      container.dispose();
      scope.dispose();
      client.close();
      await database.close();
    });

    final ok = await container
        .read(appControllerProvider.notifier)
        .signIn('https://music.example.com', 'other', 'password')
        .timeout(const Duration(seconds: 5));

    expect(ok, isFalse);
    final state = container.read(appControllerProvider);
    expect(state.cacheOwnerConflict, isTrue);
    expect(state.status, AppStatus.signedOut);
    expect(state.session, isNull);
    // Rows and pending edits are retained.
    expect((await database.allTracks()).map((t) => t.id), ['t1']);
    expect(await database.pendingOperations(), hasLength(1));
    // Marker still names the original owner.
    expect((await LibraryCacheOwnerStore().load())?.userId, 'owner');
    // Pending rows were never sent merely because a conflicting login was
    // attempted: no favorite/playlist POST may have run.
    final posts = sent.where(
      (r) => r.method == 'POST' && r.url.path.contains('Favorite'),
    );
    expect(posts, isEmpty);
    final playlistPosts = sent.where(
      (r) => r.method == 'POST' && r.url.path.contains('/Playlists/'),
    );
    expect(playlistPosts, isEmpty);
  });

  test('unknown cache blocks adoption until explicit clear', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.upsertTracks([
      TracksCompanion.insert(id: 't1', name: 'Song'),
    ]);
    // No marker: unknown cache.
    final scope = AccountScope();
    final playback = _MockPlayback();
    final downloads = _MockDownload();
    final remote = _MockRemote();
    final cast = _MockCast();
    _stubMocks(playback, downloads, remote, cast);
    final client = _authClient(
      userId: 'other',
      userName: 'Other',
      token: 'other-token',
    );
    final container = await _makeContainer(
      database: database,
      scope: scope,
      client: client,
      playback: playback,
      downloads: downloads,
      remote: remote,
      cast: cast,
    );
    addTearDown(() async {
      container.dispose();
      scope.dispose();
      client.close();
      await database.close();
    });

    final ok = await container
        .read(appControllerProvider.notifier)
        .signIn('https://music.example.com', 'other', 'password')
        .timeout(const Duration(seconds: 5));

    expect(ok, isFalse);
    expect(container.read(appControllerProvider).cacheOwnerConflict, isTrue);
    expect((await database.allTracks()).map((t) => t.id), ['t1']);
  });

  test('cancelled clear makes no changes; confirmed clear resets', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.upsertTracks([
      TracksCompanion.insert(id: 't1', name: 'Song'),
    ]);
    await database.saveFavoriteEdit('t1', true);
    await LibraryCacheOwnerStore().saveOwner(_ownerSession);
    final scope = AccountScope();
    final playback = _MockPlayback();
    final downloads = _MockDownload();
    final remote = _MockRemote();
    final cast = _MockCast();
    _stubMocks(playback, downloads, remote, cast);
    final client = _authClient(
      userId: 'other',
      userName: 'Other',
      token: 'other-token',
    );
    final container = await _makeContainer(
      database: database,
      scope: scope,
      client: client,
      playback: playback,
      downloads: downloads,
      remote: remote,
      cast: cast,
    );
    addTearDown(() async {
      container.dispose();
      scope.dispose();
      client.close();
      await database.close();
    });
    final controller = container.read(appControllerProvider.notifier);
    expect(
      await controller
          .signIn('https://music.example.com', 'other', 'password')
          .timeout(const Duration(seconds: 5)),
      isFalse,
    );
    expect(container.read(appControllerProvider).cacheOwnerConflict, isTrue);

    // Cancellation: do nothing; rows, pending, and marker stay.
    await Future<void>.delayed(Duration.zero);
    expect((await database.allTracks()).map((t) => t.id), ['t1']);
    expect(await database.pendingOperations(), hasLength(1));
    expect((await LibraryCacheOwnerStore().load())?.userId, 'owner');

    // Confirmed clear: removes library, pending, credentials, and marker,
    // clears the conflict, and does not sign in automatically.
    await controller.clearSavedLibrary().timeout(const Duration(seconds: 5));
    final state = container.read(appControllerProvider);
    expect(state.cacheOwnerConflict, isFalse);
    expect(state.status, AppStatus.signedOut);
    expect(state.session, isNull);
    expect(await database.allTracks(), isEmpty);
    expect(await database.pendingOperations(), isEmpty);
    expect(await LibraryCacheOwnerStore().load(), isNull);
  });

  testWidgets('conflict shows an explicit clear action', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.upsertTracks([
      TracksCompanion.insert(id: 't1', name: 'Song'),
    ]);
    await database.saveFavoriteEdit('t1', true);
    await LibraryCacheOwnerStore().saveOwner(_ownerSession);
    final scope = AccountScope();
    final playback = _MockPlayback();
    final downloads = _MockDownload();
    final remote = _MockRemote();
    final cast = _MockCast();
    _stubMocks(playback, downloads, remote, cast);
    final client = _authClient(
      userId: 'other',
      userName: 'Other',
      token: 'other-token',
    );
    final container = await _makeContainer(
      database: database,
      scope: scope,
      client: client,
      playback: playback,
      downloads: downloads,
      remote: remote,
      cast: cast,
    );
    addTearDown(() async {
      container.dispose();
      scope.dispose();
      client.close();
      await database.close();
    });
    await container
        .read(appControllerProvider.notifier)
        .signIn('https://music.example.com', 'other', 'password')
        .timeout(const Duration(seconds: 5));
    expect(container.read(appControllerProvider).cacheOwnerConflict, isTrue);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('different Jellyfin account'), findsOneWidget);
    expect(find.text('Clear saved library'), findsOneWidget);

    final clearButton = find.widgetWithText(
      OutlinedButton,
      'Clear saved library',
    );
    await tester.ensureVisible(clearButton);
    await tester.pumpAndSettle();
    await tester.tap(clearButton, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Clear saved library?'), findsOneWidget);
    expect(
      find.textContaining('1 saved song', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('1 pending edit', findRichText: true),
      findsOneWidget,
    );

    // Cancellation makes no changes.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect((await database.allTracks()).map((t) => t.id), ['t1']);
    expect(container.read(appControllerProvider).cacheOwnerConflict, isTrue);
  });
}
