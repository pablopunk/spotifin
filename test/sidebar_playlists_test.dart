import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/app/state/app_controller.dart';
import 'package:spotifin/features/common/artwork.dart';
import 'package:spotifin/features/common/playlist_artwork.dart';
import 'package:spotifin/features/common/track_tile.dart';
import 'package:spotifin/features/shell/sidebar_playlists.dart';
import 'package:spotifin/services/jellyfin/jellyfin_client.dart';
import 'package:spotifin/services/jellyfin/session.dart';
import 'package:spotifin/storage/database.dart';

void main() {
  testWidgets('shows playlists with drag, open, create, and rename controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.replacePlaylists([
      PlaylistsCompanion.insert(id: 'playlist', name: 'Road trip'),
    ]);
    final track = _track('track', 'album');
    Playlist? selected;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(1200, 800)),
            child: Scaffold(
              body: Row(
                children: [
                  SizedBox(
                    width: 220,
                    child: SidebarPlaylists(
                      onSelected: (playlist) => selected = playlist,
                    ),
                  ),
                  Expanded(
                    child: TrackTile(track: track, contextTracks: [track]),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Road trip'), findsOneWidget);
    expect(find.byType(DragTarget<Track>), findsOneWidget);
    expect(find.byType(Draggable<Track>), findsOneWidget);
    await tester.tap(find.text('Road trip'));
    expect(selected?.id, 'playlist');

    await tester.tap(find.byTooltip('Create playlist'));
    await tester.pumpAndSettle();
    expect(find.text('Create playlist'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Playlist options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(find.text('Rename playlist'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Playlist options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove playlist?'), findsOneWidget);
    expect(find.textContaining('deleted from Jellyfin'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    await _secondaryTap(tester, find.byType(TrackTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();
    expect(find.text('Delete song permanently?'), findsOneWidget);
    expect(find.textContaining('cannot be undone'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('deletes a playlist from Jellyfin and the local library', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final requests = <http.BaseRequest>[];
    final jellyfinClient = JellyfinClient(
      httpClient: MockClient.streaming((request, bodyStream) async {
        requests.add(request);
        final status =
            request.method == 'DELETE' && request.url.path == '/Items/playlist'
            ? 204
            : 404;
        return http.StreamedResponse(const Stream<List<int>>.empty(), status);
      }),
    );
    addTearDown(jellyfinClient.close);
    await database.replacePlaylists([
      PlaylistsCompanion.insert(id: 'playlist', name: 'Road trip'),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          jellyfinClientProvider.overrideWithValue(jellyfinClient),
          appControllerProvider.overrideWith(_AuthenticatedAppController.new),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 220,
              child: SidebarPlaylists(onSelected: (_) {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Playlist options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    final deletes = requests.where((request) => request.method == 'DELETE');
    expect(deletes, hasLength(1));
    expect(deletes.single.url.path, '/Items/playlist');
    expect(find.text('Road trip'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('uses the first four distinct album covers', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: PlaylistArtwork(
            tracks: [
              _track('1', 'a'),
              _track('2', 'a'),
              _track('3', 'b'),
              _track('4', 'c'),
              _track('5', 'd'),
              _track('6', 'e'),
            ],
            size: 100,
          ),
        ),
      ),
    );

    expect(find.byType(Artwork), findsNWidgets(4));
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

Track _track(String id, String albumId) => Track(
  id: id,
  name: 'Song $id',
  album: 'Album $albumId',
  albumId: albumId,
  artist: 'Artist',
  artistIds: '[]',
  labels: '[]',
  durationTicks: 1,
  container: 'mp3',
  favorite: false,
  playCount: 0,
  normalizationGain: null,
  albumNormalizationGain: null,
);

Future<void> _secondaryTap(WidgetTester tester, Finder finder) async {
  final position = tester.getCenter(finder);
  final gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.addPointer(location: position);
  await gesture.down(position);
  await gesture.up();
}
