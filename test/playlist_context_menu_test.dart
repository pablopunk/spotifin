import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/features/common/playlist_context_menu.dart';
import 'package:spotifin/storage/database.dart';

void main() {
  testWidgets('opens playlist actions with a secondary click', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: PlaylistContextMenu(
              playlist: _playlist(),
              tracks: [_track()],
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
    expect(find.text('Add to queue'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Rename playlist'), findsOneWidget);
    expect(find.text('Remove playlist'), findsOneWidget);

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
  artistIds: '[]',
  labels: '[]',
  durationTicks: 1,
  container: 'mp3',
  favorite: false,
  playCount: 0,
  normalizationGain: null,
  albumNormalizationGain: null,
);
