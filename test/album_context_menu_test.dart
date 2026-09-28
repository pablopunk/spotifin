import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/features/common/album_context_menu.dart';

import 'support/fake_active_playback.dart';

import 'package:spotifin/storage/database.dart';

void main() {
  setUpAll(() => registerFallbackValue(<Track>[]));

  testWidgets('opens album actions with a secondary click', (tester) async {
    final active = FakeActivePlayback();
    final tracks = [_track(), _track().copyWith(id: 'second')];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [activePlaybackProvider.overrideWithValue(active)],
        child: MaterialApp(
          home: Scaffold(
            body: AlbumContextMenu(
              title: 'Album',
              tracks: tracks,
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
    expect(find.text('Play next'), findsOneWidget);
    expect(find.text('Add to queue'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Delete album permanently'), findsOneWidget);

    await tester.tap(find.text('Play next'));
    await tester.pumpAndSettle();
    expect(active.actions, ['addNextToQueue']);
    expect(active.actionArguments['addNextToQueue'], [tracks]);

    await gesture.down(position);
    await gesture.up();
    await tester.pumpAndSettle();
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
  artistItems: '[]',
  labels: '[]',
  durationTicks: 1,
  container: 'mp3',
  favorite: false,
  playCount: 0,
  normalizationGain: null,
  albumNormalizationGain: null,
);
