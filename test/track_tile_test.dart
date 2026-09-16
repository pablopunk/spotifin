import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/app/theme.dart';
import 'package:spotifin/features/common/track_tile.dart';
import 'package:spotifin/services/playback/playback_service.dart';
import 'package:spotifin/storage/database.dart';

class _MockPlayback extends Mock implements PlaybackService {}

class _FakeTrack extends Fake implements Track {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeTrack());
    registerFallbackValue(<Track>[]);
  });
  Track makeTrack() => const Track(
    id: 'track',
    name: 'Song',
    album: 'Album',
    albumId: 'album',
    artist: 'Artist',
    artistItems: '[]',
    labels: '[]',
    durationTicks: 0,
    container: 'mp3',
    favorite: false,
    playCount: 0,
  );

  Future<AppDatabase> makeDatabase() async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    return database;
  }

  Widget contentApp({
    required Track track,
    required bool active,
    required bool playing,
    required bool hovered,
    VoidCallback? onRowTap,
    VoidCallback? onArtworkTap,
    AppDatabase? database,
  }) {
    return ProviderScope(
      overrides: [
        if (database != null) databaseProvider.overrideWithValue(database),
      ],
      child: MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: TrackTileContent(
            track: track,
            contextTracks: [track],
            downloadStatus: null,
            active: active,
            playing: playing,
            hovered: hovered,
            onRowTap: onRowTap ?? () {},
            onArtworkTap: onArtworkTap ?? () {},
          ),
        ),
      ),
    );
  }

  testWidgets('inactive row uses normal title and no indicator', (
    tester,
  ) async {
    final database = await makeDatabase();
    await tester.pumpWidget(
      contentApp(
        track: makeTrack(),
        active: false,
        playing: false,
        hovered: false,
        database: database,
      ),
    );
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.text('Song'));
    expect(title.style?.color, isNot(SpotifinColors.accent));
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    expect(find.byIcon(Icons.graphic_eq_rounded), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(database.close);
  });

  testWidgets('hovered row shows hover surface and play overlay', (
    tester,
  ) async {
    final database = await makeDatabase();
    await tester.pumpWidget(
      contentApp(
        track: makeTrack(),
        active: false,
        playing: false,
        hovered: true,
        database: database,
      ),
    );
    await tester.pumpAndSettle();

    final material = tester.widget<Material>(
      find
          .ancestor(of: find.text('Song'), matching: find.byType(Material))
          .first,
    );
    expect(material.color, SpotifinColors.hover);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(database.close);
  });

  testWidgets('current playing row shows accent title and equalizer', (
    tester,
  ) async {
    final database = await makeDatabase();
    await tester.pumpWidget(
      contentApp(
        track: makeTrack(),
        active: true,
        playing: true,
        hovered: false,
        database: database,
      ),
    );
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.text('Song'));
    expect(title.style?.color, SpotifinColors.accent);
    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(database.close);
  });

  testWidgets('current paused row shows accent title and play icon', (
    tester,
  ) async {
    final database = await makeDatabase();
    await tester.pumpWidget(
      contentApp(
        track: makeTrack(),
        active: true,
        playing: false,
        hovered: false,
        database: database,
      ),
    );
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.text('Song'));
    expect(title.style?.color, SpotifinColors.accent);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(database.close);
  });

  testWidgets('artwork and row actions stay independent', (tester) async {
    final database = await makeDatabase();
    var rows = 0;
    var artworks = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: TrackTileContent(
              track: makeTrack(),
              contextTracks: [makeTrack()],
              downloadStatus: null,
              active: false,
              playing: false,
              hovered: true,
              onRowTap: () => rows++,
              onArtworkTap: () => artworks++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(artworks, 1);
    expect(rows, 0);

    await tester.tap(find.text('Song'));
    await tester.pump();
    expect(rows, 1);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    expect(find.text('Favorite'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(database.close);
  });

  testWidgets('track tile routes artwork taps by active state', (tester) async {
    final database = await makeDatabase();
    final playback = _MockPlayback();
    final track = makeTrack();
    when(() => playback.addListener(any())).thenReturn(null);
    when(() => playback.removeListener(any())).thenReturn(null);
    when(() => playback.currentTrack).thenReturn(track);
    when(() => playback.playing).thenReturn(true);
    when(() => playback.toggle()).thenAnswer((_) async {});
    when(() => playback.playTrack(any(), any())).thenAnswer((_) async {});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          playbackProvider.overrideWithValue(playback),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: TrackTile(track: track, contextTracks: [track]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.graphic_eq_rounded));
    await tester.pump();
    verify(() => playback.toggle()).called(1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });

  testWidgets('inactive tile artwork starts that track', (tester) async {
    final database = await makeDatabase();
    final playback = _MockPlayback();
    final track = makeTrack();
    when(() => playback.addListener(any())).thenReturn(null);
    when(() => playback.removeListener(any())).thenReturn(null);
    when(() => playback.currentTrack).thenReturn(null);
    when(() => playback.playing).thenReturn(false);
    when(() => playback.playTrack(any(), any())).thenAnswer((_) async {});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          playbackProvider.overrideWithValue(playback),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: TrackTile(track: track, contextTracks: [track]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.text('Song')));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded).first);
    await tester.pump();
    verify(() => playback.playTrack(any(), any())).called(1);

    await gesture.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });
}
