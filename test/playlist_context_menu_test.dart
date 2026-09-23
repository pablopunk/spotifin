import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/features/common/playlist_context_menu.dart';
import 'package:spotifin/services/playback/playback_service.dart';
import 'package:spotifin/storage/database.dart';

class _MockPlayback extends Mock implements PlaybackService {}

void main() {
  setUpAll(() => registerFallbackValue(<Track>[]));

  testWidgets('opens playlist actions with a secondary click', (tester) async {
    final playback = _MockPlayback();
    final tracks = [_track(), _track().copyWith(id: 'second')];
    when(() => playback.addNextToQueue(any())).thenAnswer((_) async {});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playbackProvider.overrideWithValue(playback)],
        child: MaterialApp(
          home: Scaffold(
            body: PlaylistContextMenu(
              playlist: _playlist(),
              tracks: tracks,
              child: const SizedBox(width: 200, height: 200),
            ),
          ),
        ),
      ),
    );

    final position = tester.getCenter(find.byType(PlaylistContextMenu));
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.addPointer(location: position);
    await gesture.down(position);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Play'), findsOneWidget);
    expect(find.text('Play next'), findsOneWidget);
    expect(find.text('Add to queue'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Rename playlist'), findsOneWidget);
    expect(find.text('Remove playlist'), findsOneWidget);

    await tester.tap(find.text('Play next'));
    await tester.pumpAndSettle();
    verify(() => playback.addNextToQueue(tracks)).called(1);

    await gesture.down(position);
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove playlist'));
    await tester.pumpAndSettle();
    expect(find.text('Remove playlist?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
  });
}

Playlist _playlist() =>
    const Playlist(id: 'playlist', name: 'Mix', trackIds: '[]');

Track _track() => const Track(
  id: 'track',
  name: 'Song',
  album: 'Album',
  albumId: 'album',
  artist: 'Artist',
  artistItems: '[]',
  labels: '[]',
  durationTicks: 1,
  container: 'mp3',
  favorite: false,
  playCount: 0,
  normalizationGain: null,
  albumNormalizationGain: null,
);
