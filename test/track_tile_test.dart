import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/app/theme.dart';
import 'package:just_audio/just_audio.dart';
import 'package:spotifin/features/common/track_tile.dart';
import 'package:spotifin/features/common/mobile_track_queue_actions.dart';
import 'package:spotifin/services/playback/active_playback_state.dart';
import 'package:spotifin/storage/database.dart';

import 'support/fake_active_playback.dart';

class _FakeTrack extends Fake implements Track {}

ActivePlaybackState _ownerState({Track? track, bool playing = false}) =>
    ActivePlaybackState(
      destination: PlaybackDestination.local,
      track: track,
      index: track == null ? null : 0,
      entryId: track == null ? null : 'entry-0',
      queue: [?track],
      upcoming: [?track],
      upcomingOffset: 0,
      history: const [],
      playing: playing,
      position: Duration.zero,
      duration: Duration.zero,
      volumeSlider: 1,
      shuffle: false,
      repeatMode: LoopMode.off,
      busy: false,
      recovering: false,
      capabilities: PlaybackCapability.values.toSet(),
    );

ActivePlaybackState _castOwnerState({required Track track}) =>
    ActivePlaybackState(
      destination: PlaybackDestination.cast,
      track: track,
      index: 0,
      entryId: 'entry-remote',
      queue: [track],
      upcoming: [track],
      upcomingOffset: 0,
      history: const [],
      playing: true,
      position: Duration.zero,
      duration: const Duration(minutes: 3),
      volumeSlider: 0.4,
      shuffle: false,
      repeatMode: LoopMode.off,
      busy: false,
      recovering: false,
      capabilities: const {
        PlaybackCapability.transport,
        PlaybackCapability.seek,
        PlaybackCapability.volume,
        PlaybackCapability.selection,
        PlaybackCapability.queueEditing,
        PlaybackCapability.shuffle,
      },
      connectedDeviceName: 'Living Room',
    );

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
    String? downloadStatus,
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
            downloadStatus: downloadStatus,
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

  testWidgets('downloaded row shows a local download marker by its title', (
    tester,
  ) async {
    final database = await makeDatabase();
    await tester.pumpWidget(
      contentApp(
        track: makeTrack(),
        active: false,
        playing: false,
        hovered: false,
        downloadStatus: 'complete',
        database: database,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.download_done_rounded), findsOneWidget);
    expect(find.byTooltip('Downloaded on this device'), findsOneWidget);
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
    expect(find.text('Play next'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(database.close);
  });

  testWidgets('track tile routes artwork taps by active state', (tester) async {
    final database = await makeDatabase();
    final active = FakeActivePlayback();
    final track = makeTrack();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          activePlaybackProvider.overrideWithValue(active),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: TrackTile(track: track, contextTracks: [track]),
          ),
        ),
      ),
    );
    active.emit(_ownerState(track: track, playing: true));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.graphic_eq_rounded));
    await tester.pump();
    expect(active.actions, ['toggle']);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });

  testWidgets('track menu queues the selected track next', (tester) async {
    final active = FakeActivePlayback();
    final track = makeTrack();
    active.emit(_ownerState());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [activePlaybackProvider.overrideWithValue(active)],
        child: MaterialApp(
          home: Scaffold(
            body: TrackMenuButton(
              track: track,
              contextTracks: [track],
              downloadStatus: null,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play next'));
    await tester.pumpAndSettle();

    expect(active.actions, ['addNextToQueue']);
    expect(active.actionArguments['addNextToQueue'], [
      [track],
    ]);
  });

  testWidgets('song menu stays above the shell player and navigation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final track = makeTrack();
    final active = FakeActivePlayback();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [activePlaybackProvider.overrideWithValue(active)],
        child: MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Navigator(
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      body: Align(
                        alignment: const Alignment(1, 0.3),
                        child: TrackMenuButton(
                          track: track,
                          contextTracks: [track],
                          downloadStatus: null,
                        ),
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 148,
                  child: ColoredBox(color: Colors.black),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();

    expect(find.text('Download').hitTestable(), findsOneWidget);
    expect(find.text('Delete permanently').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Play next'));
    await tester.pumpAndSettle();
    expect(active.actions, ['addNextToQueue']);
  });

  testWidgets('phone hold opens the track menu', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = await makeDatabase();
    final active = FakeActivePlayback()..emit(_ownerState());
    final track = makeTrack();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          activePlaybackProvider.overrideWithValue(active),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: Scaffold(
              body: TrackTile(track: track, contextTracks: [track]),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(MobileTrackQueueActions), findsOneWidget);
    await tester.longPress(find.text('Song'));
    await tester.pumpAndSettle();
    expect(find.text('Play next'), findsNWidgets(2));
    expect(find.text('Add to queue'), findsNWidgets(2));
    await tester.tap(find.text('Play next').last);
    await tester.pumpAndSettle();
    expect(active.actions, ['addNextToQueue']);
    expect(active.actionArguments['addNextToQueue'], [
      [track],
    ]);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });

  testWidgets('phone swipe right reveals both queue actions', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = await makeDatabase();
    final active = FakeActivePlayback()..emit(_ownerState());
    final track = makeTrack();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          activePlaybackProvider.overrideWithValue(active),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: Scaffold(
              body: TrackTile(track: track, contextTracks: [track]),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(MobileTrackQueueActions), findsOneWidget);
    await tester.drag(find.text('Song'), const Offset(200, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play next'));
    await tester.pumpAndSettle();
    expect(active.actions, ['addNextToQueue']);

    await tester.drag(find.text('Song'), const Offset(200, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to queue'));
    await tester.pumpAndSettle();
    expect(active.actions, ['addNextToQueue', 'addToQueue']);
    expect(active.actionArguments['addToQueue'], [track]);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });

  testWidgets('opening another phone track closes the prior queue actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = await makeDatabase();
    final active = FakeActivePlayback()..emit(_ownerState());
    final first = makeTrack();
    final second = first.copyWith(id: 'second', name: 'Other song');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          activePlaybackProvider.overrideWithValue(active),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: Scaffold(
              body: Column(
                children: [
                  TrackTile(track: first, contextTracks: [first, second]),
                  TrackTile(track: second, contextTracks: [first, second]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    double offsetFor(String name) {
      final tile = find.ancestor(
        of: find.text(name),
        matching: find.byType(MobileTrackQueueActions),
      );
      final container = tester.widget<AnimatedContainer>(
        find.descendant(of: tile, matching: find.byType(AnimatedContainer)),
      );
      return container.transform!.storage[12];
    }

    await tester.drag(find.text('Song'), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(offsetFor('Song'), 160);
    expect(offsetFor('Other song'), 0);

    await tester.drag(find.text('Other song'), const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(offsetFor('Song'), 0);
    expect(offsetFor('Other song'), 160);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });

  testWidgets('inactive tile artwork starts that track', (tester) async {
    final database = await makeDatabase();
    final active = FakeActivePlayback()..emit(_ownerState());
    final track = makeTrack();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          activePlaybackProvider.overrideWithValue(active),
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
    expect(active.actions, ['playTrack']);
    expect(active.actionArguments['playTrack'], [
      track,
      [track],
    ]);

    await gesture.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });

  testWidgets('cast tile selection reaches the owner exactly once', (
    tester,
  ) async {
    final database = await makeDatabase();
    final active = FakeActivePlayback();
    final track = makeTrack();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          activePlaybackProvider.overrideWithValue(active),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: TrackTile(track: track, contextTracks: [track]),
          ),
        ),
      ),
    );
    active.emit(_castOwnerState(track: track));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Song'));
    await tester.pump();
    // Ordinary selections stay on Cast: exactly one owner action, and no
    // low-level local method exists on this path.
    expect(active.actions, ['playTrack']);
    expect(active.actionArguments['playTrack'], [
      track,
      [track],
    ]);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });
}
