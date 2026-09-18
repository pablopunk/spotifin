import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/app/state/app_controller.dart';
import 'package:spotifin/app/state/downtify_controller.dart';
import 'package:spotifin/services/downtify/downtify_client.dart';
import 'package:spotifin/services/downtify/downtify_models.dart';
import 'package:spotifin/services/jellyfin/jellyfin_client.dart';
import 'package:spotifin/services/jellyfin/session.dart';
import 'package:spotifin/storage/database.dart';

void main() {
  test('moves a queued song through download, scan, and import', () async {
    SharedPreferences.setMockInitialValues({
      'downtifyServerUrl': 'https://downtify.example.com',
    });
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    var remoteStatus = 'downloading';
    var scanRequests = 0;
    final downtifyClient = DowntifyClient(
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/version') {
          return http.Response(jsonEncode('2.10.2'), 200);
        }
        if (request.url.path == '/api/download/batch') {
          return http.Response(
            jsonEncode({
              'job_ids': ['external'],
              'count': 1,
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode([
            {
              'song': {
                'song_id': 'external',
                'name': 'Imported Song',
                'artists': ['Artist'],
              },
              'status': remoteStatus,
              'progress': remoteStatus == 'done' ? 100 : 40,
              'message': '',
              'filename': remoteStatus == 'done' ? 'Artist - Song.mp3' : null,
            },
          ]),
          200,
        );
      }),
    );
    final jellyfinClient = JellyfinClient(
      httpClient: MockClient((request) async {
        if (request.url.path == '/Library/Refresh') scanRequests++;
        return http.Response('', 204);
      }),
    );
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        downtifyClientProvider.overrideWithValue(downtifyClient),
        jellyfinClientProvider.overrideWithValue(jellyfinClient),
        appControllerProvider.overrideWith(_AuthenticatedAppController.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      downtifyClient.close();
      jellyfinClient.close();
      await database.close();
    });
    final subscription = container.listen(
      downtifyControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final song = DowntifySong.fromJson({
      'song_id': 'external',
      'name': 'Imported Song',
      'artists': ['Artist'],
    });

    await container.read(downtifyControllerProvider.notifier).enqueue(song);

    expect(
      container.read(downtifyControllerProvider).imports.single.status,
      'downloading',
    );

    remoteStatus = 'done';
    await container.read(downtifyControllerProvider.notifier).poll();
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    expect(scanRequests, 1);
    expect(
      container.read(downtifyControllerProvider).imports.single.status,
      'waitingForJellyfin',
    );

    await database.upsertTracks([
      TracksCompanion.insert(
        id: 'jellyfin-track',
        name: 'Imported Song',
        artist: const Value('Artist'),
      ),
    ]);
    await container.read(downtifyControllerProvider.notifier).poll();

    final state = container.read(downtifyControllerProvider);
    expect(state.imports.single.status, 'imported');
    expect(state.imports.single.matchedTrackId, 'jellyfin-track');
    expect(state.notices.single.message, contains('available'));
  });

  test('recovers polling after a transient queue failure', () async {
    SharedPreferences.setMockInitialValues({});
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    var failing = true;
    final downtifyClient = DowntifyClient(
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/version') {
          return http.Response(jsonEncode('2.10.2'), 200);
        }
        if (request.url.path == '/api/queue' && failing) {
          return http.Response('boom', 500);
        }
        return http.Response(jsonEncode(<Object>[]), 200);
      }),
    );
    final jellyfinClient = JellyfinClient(
      httpClient: MockClient((request) async => http.Response('', 204)),
    );
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        downtifyClientProvider.overrideWithValue(downtifyClient),
        jellyfinClientProvider.overrideWithValue(jellyfinClient),
        appControllerProvider.overrideWith(_AuthenticatedAppController.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      downtifyClient.close();
      jellyfinClient.close();
      await database.close();
    });
    final subscription = container.listen(
      downtifyControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final controller = container.read(downtifyControllerProvider.notifier);

    await controller.configure('https://downtify.example.com');
    await controller.poll();
    expect(
      container.read(downtifyControllerProvider).availability,
      DowntifyAvailability.unavailable,
    );

    failing = false;
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(
      container.read(downtifyControllerProvider).availability,
      DowntifyAvailability.available,
    );
  });

  test('retries a failed download three times and reports it once', () async {
    SharedPreferences.setMockInitialValues({
      'downtifyServerUrl': 'https://downtify.example.com',
    });
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    var enqueueRequests = 0;
    var removeRequests = 0;
    final client = DowntifyClient(
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/version') {
          return http.Response(jsonEncode('2.10.2'), 200);
        }
        if (request.url.path == '/api/download/batch') {
          enqueueRequests++;
          return http.Response(
            jsonEncode({
              'job_ids': ['external'],
              'count': 1,
            }),
            200,
          );
        }
        if (request.method == 'DELETE') {
          removeRequests++;
          return http.Response('{"removed":true}', 200);
        }
        return http.Response(
          jsonEncode([
            {
              'song': {
                'song_id': 'external',
                'name': 'Broken Song',
                'artists': ['Artist'],
              },
              'status': 'error',
              'progress': 20,
              'message': 'No match',
              'filename': null,
            },
          ]),
          200,
        );
      }),
    );
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        downtifyClientProvider.overrideWithValue(client),
        appControllerProvider.overrideWith(_AuthenticatedAppController.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      client.close();
      await database.close();
    });
    final subscription = container.listen(
      downtifyControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final controller = container.read(downtifyControllerProvider.notifier);
    final song = DowntifySong.fromJson({
      'song_id': 'external',
      'name': 'Broken Song',
      'artists': ['Artist'],
    });

    await controller.enqueue(song);
    await controller.poll();
    await controller.poll();
    await controller.poll();
    await controller.poll();

    final state = container.read(downtifyControllerProvider);
    expect(enqueueRequests, 4);
    expect(removeRequests, 3);
    expect(state.imports.single.retryCount, 3);
    expect(state.imports.single.status, 'downloadFailed');
    expect(state.notices, hasLength(1));

    await controller.poll();
    expect(container.read(downtifyControllerProvider).notices, hasLength(1));
    expect(enqueueRequests, 4);
  });

  test('removes a queued download remotely and locally', () async {
    SharedPreferences.setMockInitialValues({
      'downtifyServerUrl': 'https://downtify.example.com',
    });
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    var removedSongId = '';
    final client = DowntifyClient(
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/version') {
          return http.Response(jsonEncode('2.10.2'), 200);
        }
        if (request.method == 'DELETE') {
          removedSongId = request.url.queryParameters['song_id'] ?? '';
          return http.Response('{"removed":true}', 200);
        }
        return http.Response('[]', 200);
      }),
    );
    final now = DateTime(2026);
    await database.putDowntifyImport(
      DowntifyImportsCompanion.insert(
        id: 'server:user:external',
        jellyfinServerId: 'server',
        jellyfinUserId: 'user',
        downtifyUrl: 'https://downtify.example.com',
        externalSongId: 'external',
        jobId: const Value('job-id'),
        songJson: jsonEncode({
          'song_id': 'external',
          'name': 'Queued Song',
          'artists': ['Artist'],
        }),
        status: 'queued',
        createdAt: now,
        updatedAt: now,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        downtifyClientProvider.overrideWithValue(client),
        appControllerProvider.overrideWith(_AuthenticatedAppController.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      client.close();
      await database.close();
    });
    final subscription = container.listen(
      downtifyControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final item = container.read(downtifyControllerProvider).imports.single;

    await container
        .read(downtifyControllerProvider.notifier)
        .removeFromQueue(item);

    expect(removedSongId, 'job-id');
    expect(container.read(downtifyControllerProvider).imports, isEmpty);
    expect(await database.getDowntifyImports('server', 'user'), isEmpty);
  });
}

class _AuthenticatedAppController extends AppController {
  @override
  AppState build() => const AppState(
    status: AppStatus.ready,
    session: JellyfinSession(
      serverUrl: 'https://jellyfin.example.com',
      serverId: 'server',
      deviceId: 'device',
      userId: 'user',
      userName: 'Pablo',
      accessToken: 'token',
    ),
  );

  @override
  Future<void> refresh({bool silent = false, bool force = false}) async {}
}
