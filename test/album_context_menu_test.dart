import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/features/common/album_context_menu.dart';
import 'package:spotifin/storage/database.dart';

void main() {
  testWidgets('opens album actions with a secondary click', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AlbumContextMenu(
              title: 'Album',
              tracks: [_track()],
              child: const SizedBox(width: 200, height: 200),
            ),
          ),
        ),
      ),
    );

    final position = tester.getCenter(find.byType(AlbumContextMenu));
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
    expect(find.text('Delete album permanently'), findsOneWidget);

    await tester.tap(find.text('Delete album permanently'));
    await tester.pumpAndSettle();
    expect(find.text('Delete album permanently?'), findsOneWidget);
    expect(find.textContaining('cannot be undone'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
  });
}

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
