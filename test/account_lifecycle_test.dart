import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/app/state/app_controller.dart';
import 'package:spotifin/services/cast/cast_controller.dart';
import 'package:spotifin/services/downloads/download_service.dart';
import 'package:spotifin/services/jellyfin/account_scope.dart';
import 'package:spotifin/services/jellyfin/jellyfin_client.dart';
import 'package:spotifin/services/jellyfin/session.dart';
import 'package:spotifin/services/playback/playback_service.dart';
import 'package:spotifin/services/playback/remote_session_service.dart';
import 'package:spotifin/storage/database.dart';

const _sessionA = JellyfinSession(
  serverUrl: 'https://music.example.com',
  serverId: 'server',
  deviceId: 'device',
  userId: 'user-a',
  userName: 'User A',
  accessToken: 'token-a',
);

const _sessionB = JellyfinSession(
  serverUrl: 'https://music.example.com',
  serverId: 'server',
  deviceId: 'device',
  userId: 'user-b',
  userName: 'User B',
  accessToken: 'token-b',
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
  when(() => playback.addListener(any())).thenReturn(null);
  when(() => playback.removeListener(any())).thenReturn(null);
  when(() => downloads.addListener(any())).thenReturn(null);
  when(() => downloads.removeListener(any())).thenReturn(null);
  when(() => remote.addListener(any())).thenReturn(null);
  when(() => remote.removeListener(any())).thenReturn(null);
  when(() => cast.addListener(any())).thenReturn(null);
  when(() => cast.removeListener(any())).thenReturn(null);
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
  when(() => cast.configure(any())).thenReturn(null);
  when(() => cast.disconnect(resumeLocal: any(named: 'resumeLocal')))
      .thenAnswer((_) async {});
}

void main() {
  setUpAll(() {
    registerFallbackValue(_sessionA);
    registerFallbackValue(<Track>[]);
    registerFallbackValue('fallback');
    registerFallbackValue(const Duration(seconds: 1));
  });

  group('AccountScope', () {
    test('invalidation clears the lease synchronously and notifies', () {
      final scope = AccountScope();
      addTearDown(scope.dispose);
      var notifications = 0;
      scope.addListener(() => notifications++);
      final lease = scope.activate(_sessionA);
      expect(scope.current, isNotNull);
      expect(scope.isCurrent(lease), isTrue);
      notifications = 0;

      scope.invalidate();

      expect(scope.current, isNull);
      expect(scope.isCurrent(lease), isFalse);
      expect(notifications, 1);
    });

    test('isCurrent compares generation and owner, not identity', () {
      final scope = AccountScope();
      addTearDown(scope.dispose);
      final lease = scope.activate(_sessionA);
      const refreshed = JellyfinSession(
        serverUrl: 'https://music.example.com',
        serverId: 'server',
        deviceId: 'device',
        userId: 'user-a',
        userName: 'Renamed',
        accessToken: 'token-a',
      );
      final next = scope.updateSession(lease, refreshed);

      expect(next.generation, lease.generation);
      expect(scope.isCurrent(lease), isTrue);
      expect(scope.isCurrent(next), isTrue);
      expect(next.session.userName, 'Renamed');
    });

    test('updateSession rejects an owner change', () {
      final scope = AccountScope();
      addTearDown(scope.dispose);
      final lease = scope.activate(_sessionA);
      expect(
        () => scope.updateSession(lease, _sessionB),
        throwsA(isA<StateError>()),
      );
      expect(scope.isCurrent(lease), isTrue);
    });

    test('stale queued commits are skipped with an explicit result', () async {
      final scope = AccountScope();
      addTearDown(scope.dispose);
      final lease = scope.activate(_sessionA);
      var wrote = false;
      final pending = scope.commit(lease, () async {
        wrote = true;
      });
      scope.invalidate();
      final result = await pending;
      expect(result, AccountWriteResult.stale);
      expect(wrote, isFalse);
    });

    test('running commit finishes before a queued clear', () async {
      final scope = AccountScope();
      addTearDown(scope.dispose);
      final lease = scope.activate(_sessionA);
      final writeStarted = Completer<void>();
      final allowWrite = Completer<void>();
      var writeFinished = false;
      var clearRan = false;
      var clearSawWrite = false;

      final commitFuture = scope.commit(lease, () async {
        writeStarted.complete();
        await allowWrite.future;
        writeFinished = true;
      });
      final clearFuture = scope.exclusive(() async {
        clearRan = true;
        clearSawWrite = writeFinished;
      });

      await writeStarted.future;
      // The clear fence must wait for the already-started write.
      await Future<void>.delayed(Duration.zero);
      expect(clearRan, isFalse);

      allowWrite.complete();
      expect(await commitFuture, AccountWriteResult.applied);
      await clearFuture;
      expect(writeFinished, isTrue);
      expect(clearRan, isTrue);
      expect(clearSawWrite, isTrue);
    });

    test('queued activation cannot revive an invalidated account', () async {
      final scope = AccountScope();
      addTearDown(scope.dispose);
      scope.activate(_sessionA);
      final attempt = scope.generation;
      var activated = false;
      final queued = scope.exclusive(() async {
        if (scope.generation != attempt) return;
        scope.activate(_sessionB);
        activated = true;
      });
      scope.invalidate();
      await queued;
      expect(activated, isFalse);
      expect(scope.current, isNull);
    });

    test('fence rejects recursive acquisition', () async {
      final scope = AccountScope();
      addTearDown(scope.dispose);
      var threw = false;
      await scope.exclusive(() async {
        try {
          await scope.exclusive(() async {});
        } on StateError {
          threw = true;
        }
      });
      expect(threw, isTrue);

      final lease = scope.activate(_sessionA);
      var commitThrew = false;
      await scope.exclusive(() async {
        try {
          await scope.commit(lease, () async {});
        } on StateError {
          commitThrew = true;
        }
      });
      expect(commitThrew, isTrue);
    });
  });

  group('AppController account guards', () {
    test('late identity refresh cannot save after sign-out', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final scope = AccountScope();
      final playback = _MockPlayback();
      final downloads = _MockDownload();
      final remote = _MockRemote();
      final cast = _MockCast();
      _stubMocks(playback, downloads, remote, cast);
      final identityGate = Completer<void>();
      final identityStarted = Completer<void>();
      final requests = <http.Request>[];
      final client = JellyfinClient(
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/System/Info/Public') {
            return http.Response('{"Id":"server"}', 200);
          }
          if (request.url.path == '/Users/AuthenticateByName') {
            return http.Response(
              '{"AccessToken":"token-a","User":{"Id":"user-a","Name":"User A"}}',
              200,
            );
          }
          if (request.url.path == '/Users/Me') {
            if (!identityStarted.isCompleted) identityStarted.complete();
            await identityGate.future;
            return http.Response(
              '{"Id":"user-a","Name":"User A","ServerId":"server"}',
              200,
            );
          }
          if (request.url.path.contains('/Items')) {
            return http.Response('{"Items":[],"TotalRecordCount":0}', 200);
          }
          if (request.url.path == '/Playlists/p/Items') {
            return http.Response('', 204);
          }
          return http.Response('', 204);
        }),
      );
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
      addTearDown(() async {
        container.dispose();
        scope.dispose();
        client.close();
        await database.close();
      });

      final controller = container.read(appControllerProvider.notifier);
      final signInFuture = controller.signIn(
        'https://music.example.com',
        'user-a',
        'password',
      );
      // signIn ends with a refresh that gates on /Users/Me.
      await identityStarted.future.timeout(const Duration(seconds: 5));
      await controller.signOut();
      identityGate.complete();
      final signInResult = await signInFuture.timeout(
        const Duration(seconds: 5),
      );

      expect(signInResult, isFalse);
      expect(container.read(appControllerProvider).status, AppStatus.signedOut);
      expect(container.read(appControllerProvider).session, isNull);
      expect(await database.allTracks(), isEmpty);
    });

    test('history fetched after sign-out never writes rows', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final scope = AccountScope();
      final playback = _MockPlayback();
      final downloads = _MockDownload();
      final remote = _MockRemote();
      final cast = _MockCast();
      _stubMocks(playback, downloads, remote, cast);
      final historyGate = Completer<void>();
      final historyStarted = Completer<void>();
      final client = JellyfinClient(
        httpClient: MockClient((request) async {
          if (request.url.path == '/System/Info/Public') {
            return http.Response('{"Id":"server"}', 200);
          }
          if (request.url.path == '/Users/AuthenticateByName') {
            return http.Response(
              '{"AccessToken":"token-a","User":{"Id":"user-a","Name":"User A"}}',
              200,
            );
          }
          if (request.url.path == '/Users/Me') {
            return http.Response(
              '{"Id":"user-a","Name":"User A","ServerId":"server"}',
              200,
            );
          }
          if (request.url.queryParameters['Filters'] == 'IsPlayed') {
            if (!historyStarted.isCompleted) historyStarted.complete();
            await historyGate.future;
            return http.Response('{"Items":[],"TotalRecordCount":0}', 200);
          }
          if (request.url.path.contains('/Items')) {
            return http.Response('{"Items":[],"TotalRecordCount":0}', 200);
          }
          return http.Response('', 204);
        }),
      );
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
      addTearDown(() async {
        container.dispose();
        scope.dispose();
        client.close();
        await database.close();
      });

      final controller = container.read(appControllerProvider.notifier);
      expect(
        await controller
            .signIn('https://music.example.com', 'user-a', 'password')
            .timeout(const Duration(seconds: 5)),
        isTrue,
      );
      final historyFuture = controller.refreshHistory();
      await historyStarted.future.timeout(const Duration(seconds: 5));
      await controller.signOut();
      historyGate.complete();
      await historyFuture.timeout(const Duration(seconds: 5));

      expect(await database.allTracks(), isEmpty);
      expect(container.read(appControllerProvider).status, AppStatus.signedOut);
    });

    test('second overlapping sign-in wins and first cannot publish', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final scope = AccountScope();
      final playback = _MockPlayback();
      final downloads = _MockDownload();
      final remote = _MockRemote();
      final cast = _MockCast();
      _stubMocks(playback, downloads, remote, cast);
      final firstGate = Completer<void>();
      final client = JellyfinClient(
        httpClient: MockClient((request) async {
          if (request.url.path == '/System/Info/Public') {
            return http.Response('{"Id":"server"}', 200);
          }
          if (request.url.path == '/Users/AuthenticateByName') {
            final body = request.body;
            if (body.contains('first')) {
              await firstGate.future;
              return http.Response(
                '{"AccessToken":"token-a","User":{"Id":"user-a","Name":"First"}}',
                200,
              );
            }
            return http.Response(
              '{"AccessToken":"token-b","User":{"Id":"user-b","Name":"Second"}}',
              200,
            );
          }
          if (request.url.path == '/Users/Me') {
            return http.Response(
              '{"Id":"user-b","Name":"Second","ServerId":"server"}',
              200,
            );
          }
          if (request.url.path.contains('/Items')) {
            return http.Response('{"Items":[],"TotalRecordCount":0}', 200);
          }
          return http.Response('', 204);
        }),
      );
      // Pre-seed an owner conflict-free start: no marker, empty cache.
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
      addTearDown(() async {
        container.dispose();
        scope.dispose();
        client.close();
        await database.close();
      });
      final controller = container.read(appControllerProvider.notifier);
      final first = controller.signIn(
        'https://music.example.com',
        'first',
        'password',
      );
      // Let the first request reach the gate.
      await Future<void>.delayed(Duration.zero);
      final second = await controller
          .signIn('https://music.example.com', 'second', 'password')
          .timeout(const Duration(seconds: 5));
      // The second sign-in used an unknown cache with a valid new session:
      // the first sign-in already assigned the owner? No marker yet and both
      // raced on an empty cache. The second wins; releasing the first must
      // not overwrite it.
      firstGate.complete();
      final firstResult = await first.timeout(const Duration(seconds: 5));

      expect(second, isTrue);
      expect(firstResult, isFalse);
      expect(container.read(appControllerProvider).session?.userId, 'user-b');
    });

    test('old refresh cannot resume downloads after new activation', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final scope = AccountScope();
      final playback = _MockPlayback();
      final downloads = _MockDownload();
      final remote = _MockRemote();
      final cast = _MockCast();
      _stubMocks(playback, downloads, remote, cast);
      final tracksGate = Completer<void>();
      final tracksStarted = Completer<void>();
      var resumeCalls = 0;
      when(() => downloads.resume(any(), any(), small: any(named: 'small')))
          .thenAnswer((_) async {
            resumeCalls++;
          });
      final client = JellyfinClient(
        httpClient: MockClient((request) async {
          if (request.url.path == '/System/Info/Public') {
            return http.Response('{"Id":"server"}', 200);
          }
          if (request.url.path == '/Users/AuthenticateByName') {
            return http.Response(
              '{"AccessToken":"token-a","User":{"Id":"user-a","Name":"User A"}}',
              200,
            );
          }
          if (request.url.path == '/Users/Me') {
            return http.Response(
              '{"Id":"user-a","Name":"User A","ServerId":"server"}',
              200,
            );
          }
          if (request.url.path.contains('/Items') &&
              request.url.queryParameters['IncludeItemTypes'] == 'Audio' &&
              request.url.queryParameters['Filters'] != 'IsPlayed') {
            if (!tracksStarted.isCompleted) tracksStarted.complete();
            await tracksGate.future;
            return http.Response('{"Items":[],"TotalRecordCount":0}', 200);
          }
          if (request.url.path.contains('/Items')) {
            return http.Response('{"Items":[],"TotalRecordCount":0}', 200);
          }
          return http.Response('', 204);
        }),
      );
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
      addTearDown(() async {
        container.dispose();
        scope.dispose();
        client.close();
        await database.close();
      });
      final controller = container.read(appControllerProvider.notifier);
      // Sign in without triggering the gated track fetch: signIn calls
      // refresh() which will gate; run it in the background.
      final signInFuture = controller.signIn(
        'https://music.example.com',
        'user-a',
        'password',
      );
      await tracksStarted.future.timeout(const Duration(seconds: 5));
      final resumesBefore = resumeCalls;
      await controller.signOut();
      tracksGate.complete();
      await signInFuture.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(Duration.zero);
      expect(resumeCalls, resumesBefore);
      expect(container.read(appControllerProvider).status, AppStatus.signedOut);
    });
  });
}
