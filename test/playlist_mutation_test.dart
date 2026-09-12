import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/app/state/app_controller.dart';
import 'package:spotifin/services/jellyfin/jellyfin_client.dart';
import 'package:spotifin/services/jellyfin/session.dart';
import 'package:spotifin/storage/database.dart';

void main() {
  test('adds a song to a playlist without refetching playlists', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final requests = <http.Request>[];
    final jellyfinClient = JellyfinClient(
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'POST' &&
            request.url.path == '/Playlists/p1/Items') {
          return http.Response('', 204);
        }
        return http.Response('', 404);
      }),
    );
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        jellyfinClientProvider.overrideWithValue(jellyfinClient),
        appControllerProvider.overrideWith(_AuthenticatedAppController.new),
      ],
    );
    addTearDown(() async {
      container.dispose();
      jellyfinClient.close();
      await database.close();
    });
    await database.replacePlaylists([
      PlaylistsCompanion.insert(id: 'p1', name: 'Mix'),
    ]);

    await container
        .read(appControllerProvider.notifier)
        .addToPlaylist('p1', 't1');

    final gets = requests.where((request) => request.method == 'GET');
    expect(gets, isEmpty);
    final posts = requests.where(
      (request) =>
          request.method == 'POST' && request.url.path == '/Playlists/p1/Items',
    );
    expect(posts, hasLength(1));
    expect(posts.single.url.queryParameters['ids'], 't1');
    expect(posts.single.url.queryParameters['userId'], 'user');
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
}
