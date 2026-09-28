import 'dart:convert';

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
import 'package:spotifin/services/jellyfin/library_cache_owner_store.dart';
import 'package:spotifin/services/jellyfin/session.dart';
import 'package:spotifin/services/playback/playback_service.dart';
import 'package:spotifin/services/playback/remote_session_service.dart';
import 'package:spotifin/storage/database.dart';

const _session = JellyfinSession(
  serverUrl: 'https://music.example.com',
  serverId: 'server',
  deviceId: 'device',
  userId: 'user',
  userName: 'User',
  accessToken: 'token',
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

JellyfinClient _clientFor(Map<String, http.Response Function()> routes) =>
    JellyfinClient(
      httpClient: MockClient((request) async {
        for (final entry in routes.entries) {
          if (request.url.path == entry.key) return entry.value();
        }
        if (request.url.path.contains('/Items')) {
          return http.Response('{"Items":[],"TotalRecordCount":0}', 200);
        }
        return http.Response('', 204);
      }),
    );

void main() {
  setUpAll(() {
    registerFallbackValue(_session);
    registerFallbackValue(<Track>[]);
  });

  group('LibraryCacheOwnerStore', () {
    test('saves and loads a JSON tuple without secrets', () async {
      SharedPreferences.setMockInitialValues({});
      final store = LibraryCacheOwnerStore();

      await store.saveOwner(_session);
      final loaded = await store.load();

      expect(loaded?.serverUrl, 'https://music.example.com');
      expect(loaded?.serverId, 'server');
      expect(loaded?.userId, 'user');
      expect(loaded?.key, accountOwnerKeyForSession(_session));
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(LibraryCacheOwnerStore.storageKey)!;
      expect(raw, contains('music.example.com'));
      expect(raw, isNot(contains('token')));
      expect(raw, isNot(contains('User')));
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(
        decoded.keys,
        unorderedEquals(['serverUrl', 'serverId', 'userId']),
      );
    });

    test('normalizes cosmetic URL differences to one owner', () async {
      SharedPreferences.setMockInitialValues({});
      final store = LibraryCacheOwnerStore();
      const variants = [
        'https://music.example.com/',
        'https://MUSIC.example.com',
        'music.example.com',
        '  https://music.example.com  ',
      ];
      for (final variant in variants) {
        await store.saveOwner(
          JellyfinSession(
            serverUrl: variant,
            serverId: 'server',
            deviceId: 'device',
            userId: 'user',
            userName: 'User',
            accessToken: 'token',
          ),
        );
        expect((await store.load())?.key, accountOwnerKeyForSession(_session));
      }
    });

    test('matches only the same normalized account', () async {
      SharedPreferences.setMockInitialValues({});
      final store = LibraryCacheOwnerStore();
      await store.saveOwner(_session);
      final marker = await store.load();
      expect(store.matches(marker, _session), isTrue);
      const other = JellyfinSession(
        serverUrl: 'https://music.example.com',
        serverId: 'server',
        deviceId: 'device',
        userId: 'other',
        userName: 'Other',
        accessToken: 'token',
      );
      expect(store.matches(marker, other), isFalse);
      expect(store.matches(null, _session), isFalse);
    });

    test('returns null for missing or corrupt markers and clears', () async {
      SharedPreferences.setMockInitialValues({});
      final store = LibraryCacheOwnerStore();
      expect(await store.load(), isNull);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(LibraryCacheOwnerStore.storageKey, 'not-json');
      expect(await store.load(), isNull);
      await store.saveOwner(_session);
      expect(await store.load(), isNotNull);
      await store.clear();
      expect(await store.load(), isNull);
    });
  });

  group('cache ownership policy', () {
    test('empty cache assigns the owner before ready', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final scope = AccountScope();
      final playback = _MockPlayback();
      final downloads = _MockDownload();
      final remote = _MockRemote();
      final cast = _MockCast();
      _stubMocks(playback, downloads, remote, cast);
      final client = _clientFor({
        '/System/Info/Public': () => http.Response('{"Id":"server"}', 200),
        '/Users/AuthenticateByName': () => http.Response(
          '{"AccessToken":"token","User":{"Id":"user","Name":"User"}}',
          200,
        ),
        '/Users/Me': () => http.Response(
          '{"Id":"user","Name":"User","ServerId":"server"}',
          200,
        ),
      });
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

      final ok = await container
          .read(appControllerProvider.notifier)
          .signIn('https://music.example.com', 'user', 'password')
          .timeout(const Duration(seconds: 5));
      expect(ok, isTrue);
      expect(container.read(appControllerProvider).status, AppStatus.ready);
      final marker = await LibraryCacheOwnerStore().load();
      expect(marker?.key, accountOwnerKeyForSession(_session));
    });

    test('legacy cache migrates ownership from the saved session', () async {
      SharedPreferences.setMockInitialValues({
        'serverUrl': 'https://music.example.com',
        'serverId': 'server',
        'deviceId': 'device',
        'userId': 'user',
        'userName': 'User',
      });
      FlutterSecureStorage.setMockInitialValues({'accessToken': 'token'});
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      await database.upsertTracks([
        TracksCompanion.insert(id: 't1', name: 'Song'),
      ]);
      final scope = AccountScope();
      final playback = _MockPlayback();
      final downloads = _MockDownload();
      final remote = _MockRemote();
      final cast = _MockCast();
      _stubMocks(playback, downloads, remote, cast);
      final client = _clientFor({
        '/Users/Me': () => http.Response(
          '{"Id":"user","Name":"User","ServerId":"server"}',
          200,
        ),
      });
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
      await controller.initialize().timeout(const Duration(seconds: 5));
      // Wait for the background refresh triggered by initialize.
      await controller.refresh(force: true).timeout(const Duration(seconds: 5));

      expect(container.read(appControllerProvider).status, AppStatus.ready);
      expect((await database.allTracks()).map((t) => t.id), isEmpty);
      // Legacy rows were replaced by the (empty) server snapshot, but the
      // migrated owner marker must remain.
      final marker = await LibraryCacheOwnerStore().load();
      expect(marker?.userId, 'user');
    });

    test('expiry clears credentials but retains cache and marker', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final scope = AccountScope();
      final playback = _MockPlayback();
      final downloads = _MockDownload();
      final remote = _MockRemote();
      final cast = _MockCast();
      _stubMocks(playback, downloads, remote, cast);
      var unauthorized = false;
      final client = JellyfinClient(
        httpClient: MockClient((request) async {
          if (request.url.path == '/System/Info/Public') {
            return http.Response('{"Id":"server"}', 200);
          }
          if (request.url.path == '/Users/AuthenticateByName') {
            return http.Response(
              '{"AccessToken":"token","User":{"Id":"user","Name":"User"}}',
              200,
            );
          }
          if (request.url.path == '/Users/Me') {
            if (unauthorized) return http.Response('Unauthorized', 401);
            return http.Response(
              '{"Id":"user","Name":"User","ServerId":"server"}',
              200,
            );
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
            .signIn('https://music.example.com', 'user', 'password')
            .timeout(const Duration(seconds: 5)),
        isTrue,
      );
      await database.upsertTracks([
        TracksCompanion.insert(id: 'kept', name: 'Kept'),
      ]);
      unauthorized = true;
      await controller.refresh(force: true).timeout(const Duration(seconds: 5));

      expect(container.read(appControllerProvider).status, AppStatus.signedOut);
      expect((await database.allTracks()).map((t) => t.id), ['kept']);
      expect(await LibraryCacheOwnerStore().load(), isNotNull);
    });

    test('explicit sign-out clears account data and the marker', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final scope = AccountScope();
      final playback = _MockPlayback();
      final downloads = _MockDownload();
      final remote = _MockRemote();
      final cast = _MockCast();
      _stubMocks(playback, downloads, remote, cast);
      final client = _clientFor({
        '/System/Info/Public': () => http.Response('{"Id":"server"}', 200),
        '/Users/AuthenticateByName': () => http.Response(
          '{"AccessToken":"token","User":{"Id":"user","Name":"User"}}',
          200,
        ),
        '/Users/Me': () => http.Response(
          '{"Id":"user","Name":"User","ServerId":"server"}',
          200,
        ),
      });
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
            .signIn('https://music.example.com', 'user', 'password')
            .timeout(const Duration(seconds: 5)),
        isTrue,
      );
      await database.upsertTracks([
        TracksCompanion.insert(id: 't1', name: 'Song'),
      ]);
      await controller.signOut().timeout(const Duration(seconds: 5));

      expect(await database.allTracks(), isEmpty);
      expect(await LibraryCacheOwnerStore().load(), isNull);
      expect(container.read(appControllerProvider).status, AppStatus.signedOut);
    });
  });
}
