import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/app/state/app_controller.dart';
import 'package:spotifin/services/downtify/downtify_client.dart';
import 'package:spotifin/services/downtify/downtify_models.dart';
import 'package:spotifin/services/jellyfin/jellyfin_client.dart';
import 'package:spotifin/services/jellyfin/session.dart';
import 'package:spotifin/storage/database.dart';

const _session = JellyfinSession(
  serverUrl: 'https://jellyfin.example.com',
  serverId: 'server',
  deviceId: 'device',
  userId: 'user',
  userName: 'Pablo',
  accessToken: 'token',
);

class _CountingAppController extends AppController {
  @override
  AppState build() =>
      const AppState(status: AppStatus.ready, session: _session);

  int refreshCalls = 0;

  @override
  Future<void> refresh({bool silent = false, bool force = false}) async {
    refreshCalls++;
  }
}

void main() {
  test('imports a track fetched through the real library interface', () async {
    SharedPreferences.setMockInitialValues({
      'downtifyServerUrl': 'https://downtify.example.com',
    });
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    var remoteStatus = 'downloading';
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
                'name': 'Library Song',
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
        if (request.method == 'GET' &&
            request.url.path.endsWith('/Items') &&
            request.url.queryParameters['IncludeItemTypes'] == 'Audio') {
          return http.Response(
            jsonEncode({
              'Items': [
                {
                  'Id': 'jellyfin-track',
                  'Name': 'Library Song',
                  'Artists': ['Artist'],
                },
              ],
              'TotalRecordCount': 1,
            }),
            200,
          );
        }
        return http.Response('', 204);
      }),
    );
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        downtifyClientProvider.overrideWithValue(downtifyClient),
        jellyfinClientProvider.overrideWithValue(jellyfinClient),
        appControllerProvider.overrideWith(_CountingAppController.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      downtifyClient.close();
      jellyfinClient.close();
      await database.close();
    });
    container.read(accountScopeProvider).activate(_session);
    final subscription = container.listen(
      downtifyControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final song = DowntifySong.fromJson({
      'song_id': 'external',
      'name': 'Library Song',
      'artists': ['Artist'],
    });
    await container.read(downtifyControllerProvider.notifier).enqueue(song);
    remoteStatus = 'done';
    await container.read(downtifyControllerProvider.notifier).poll();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    // Ten-second catalog throttle: force the waiting check through.
    await container.read(downtifyControllerProvider.notifier).poll();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final state = container.read(downtifyControllerProvider);
    expect(state.imports.single.status, 'imported');
    expect(state.imports.single.matchedTrackId, 'jellyfin-track');
    // The persisted track exists only because the track refresh wrote it.
    expect(
      (await database.allTracks()).map((track) => track.id),
      contains('jellyfin-track'),
    );
    // No full app refresh orchestration was invoked for the import path.
    expect(
      (container.read(
        appControllerProvider.notifier,
      ) as _CountingAppController).refreshCalls,
      0,
    );
  });

  test('failed and stale library results leave waiting rows unchanged', () async {
    SharedPreferences.setMockInitialValues({
      'downtifyServerUrl': 'https://downtify.example.com',
    });
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
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
                'name': 'Waiting Song',
                'artists': ['Artist'],
              },
              'status': 'done',
              'progress': 100,
              'message': '',
              'filename': 'Artist - Song.mp3',
            },
          ]),
          200,
        );
      }),
    );
    // Track refresh fails: waiting rows must not become imported or timed out.
    final jellyfinClient = JellyfinClient(
      httpClient: MockClient((request) async {
        if (request.method == 'GET' &&
            request.url.path.endsWith('/Items') &&
            request.url.queryParameters['IncludeItemTypes'] == 'Audio') {
          return http.Response('boom', 500);
        }
        return http.Response('', 204);
      }),
    );
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        downtifyClientProvider.overrideWithValue(downtifyClient),
        jellyfinClientProvider.overrideWithValue(jellyfinClient),
        appControllerProvider.overrideWith(_CountingAppController.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      downtifyClient.close();
      jellyfinClient.close();
    });
    container.read(accountScopeProvider).activate(_session);
    final subscription = container.listen(
      downtifyControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final song = DowntifySong.fromJson({
      'song_id': 'external',
      'name': 'Waiting Song',
      'artists': ['Artist'],
    });
    await container.read(downtifyControllerProvider.notifier).enqueue(song);
    await container.read(downtifyControllerProvider.notifier).poll();
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    expect(
      container.read(downtifyControllerProvider).imports.single.status,
      'waitingForJellyfin',
    );
    await container.read(downtifyControllerProvider.notifier).poll();
    expect(
      container.read(downtifyControllerProvider).imports.single.status,
      'waitingForJellyfin',
    );
  });
}
