import 'dart:ui' show PointerDeviceKind;

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

    await tester.drag(find.byType(PageView), const Offset(-40, 0));
    await tester.pumpAndSettle();

    expect(changedIndexes, isEmpty);
  });

  testWidgets('dragging with the mouse changes the playing track', (
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
                tracks: [_track('one'), _track('two'), _track('three')],
                currentIndex: 1,
                onTrackChanged: (index) async => changedIndexes.add(index),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.byType(PageView));
    final gesture = await tester.startGesture(
      center,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(-220, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(changedIndexes, [2]);
  });

  testWidgets('shows complete previous and next artwork around current', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: SizedBox(
              width: 700,
              height: 400,
              child: PlayerArtworkCarousel(
                tracks: [_track('one'), _track('two'), _track('three')],
                currentIndex: 1,
                onTrackChanged: (_) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final viewport = tester.getRect(find.byType(PageView));
    final previous = tester.getRect(find.byKey(const ValueKey('one')));
    final current = tester.getRect(find.byKey(const ValueKey('two')));
    final next = tester.getRect(find.byKey(const ValueKey('three')));

    expect(viewport.contains(previous.topLeft), isTrue);
    expect(viewport.contains(previous.bottomRight), isTrue);
    expect(viewport.contains(next.topLeft), isTrue);
    expect(viewport.contains(next.bottomRight), isTrue);
    expect(current.width, greaterThan(previous.width));
    expect(current.width, greaterThan(next.width));
  });

  testWidgets('a swipe does not replace artwork with a fixed foreground', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: SizedBox(
              width: 390,
              height: 390,
              child: PlayerArtworkCarousel(
                tracks: [_track('one'), _track('two'), _track('three')],
                currentIndex: 1,
                onTrackChanged: (_) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final currentArt = tester.element(find.byKey(const ValueKey('two')));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    await gesture.moveBy(const Offset(-60, 0));
    await tester.pump();

    expect(tester.element(find.byKey(const ValueKey('two'))), same(currentArt));
    expect(find.byKey(const ValueKey('foreground-two')), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a long drag advances only one track', (tester) async {
    final tracks = [
      _track('zero'),
      _track('one'),
      _track('two'),
      _track('three'),
      _track('four'),
    ];
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

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(changedIndexes, [2]);
  });

  testWidgets(
    'a high-velocity fling advances only one track without chaining',
    (tester) async {
      final tracks = [
        _track('zero'),
        _track('one'),
        _track('two'),
        _track('three'),
        _track('four'),
      ];
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

      await tester.fling(find.byType(PageView), const Offset(-400, 0), 3000);
      await tester.pumpAndSettle();

      expect(changedIndexes, [2]);
    },
  );

  testWidgets('a high-velocity fling back goes back only one track', (
    tester,
  ) async {
    final tracks = [
      _track('zero'),
      _track('one'),
      _track('two'),
      _track('three'),
      _track('four'),
    ];
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
                currentIndex: 2,
                onTrackChanged: (index) async => changedIndexes.add(index),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.fling(find.byType(PageView), const Offset(400, 0), 3000);
    await tester.pumpAndSettle();

    expect(changedIndexes, [1]);
  });

  testWidgets('two successive swipes each move one track', (tester) async {
    final tracks = [
      _track('zero'),
      _track('one'),
      _track('two'),
      _track('three'),
      _track('four'),
    ];
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
                currentIndex: 0,
                onTrackChanged: (index) async => changedIndexes.add(index),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(PageView), const Offset(-220, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(-220, 0));
    await tester.pumpAndSettle();

    expect(changedIndexes, [1, 2]);
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
