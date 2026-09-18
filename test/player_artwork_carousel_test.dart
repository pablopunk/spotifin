import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/app/theme.dart';
import 'package:spotifin/features/common/artwork.dart';
import 'package:spotifin/features/player/player_artwork_carousel.dart';
import 'package:spotifin/storage/database.dart';

void main() {
  testWidgets('swiping past a page threshold changes the playing track', (
    tester,
  ) async {
    final tracks = [_track('one'), _track('two'), _track('three')];
    final changedIndexes = <int>[];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: SizedBox(
              width: 390,
              height: 390,
              child: PlayerArtworkCarousel(
                tracks: tracks,
                currentIndex: 1,
                onTrackChanged: (index) async => changedIndexes.add(index),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Artwork), findsAtLeastNWidgets(2));

    await tester.drag(find.byType(PageView), const Offset(-220, 0));
    await tester.pumpAndSettle();

    expect(changedIndexes, [2]);
  });

  testWidgets('a short swipe settles back without changing tracks', (
    tester,
  ) async {
    final changedIndexes = <int>[];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: SizedBox(
              width: 390,
              height: 390,
              child: PlayerArtworkCarousel(
                tracks: [_track('one'), _track('two')],
                currentIndex: 0,
                onTrackChanged: (index) async => changedIndexes.add(index),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(PageView), const Offset(-70, 0));
    await tester.pumpAndSettle();

    expect(changedIndexes, isEmpty);
  });
}

Track _track(String id) => Track(
  id: id,
  name: 'Song $id',
  album: 'Album $id',
  albumId: 'album-$id',
  artist: 'Artist',
  artistItems: '[]',
  labels: '[]',
  durationTicks: 0,
  container: 'mp3',
  favorite: false,
  playCount: 0,
);
