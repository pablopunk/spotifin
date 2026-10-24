import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/features/common/design_system.dart';
import 'package:spotifin/features/common/playlist_artwork.dart';
import 'package:spotifin/features/common/track_tile.dart';
import 'package:spotifin/features/home/home_screen.dart';
import 'package:spotifin/services/playback/active_playback.dart';
import 'package:spotifin/storage/database.dart';

import 'support/fake_active_playback.dart';

void main() {
  testWidgets('home recently played includes live and session playback', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.upsertTracks([
      TracksCompanion.insert(
        id: 'server-recent',
        name: 'Older Song',
        artist: const Value('Artist'),
        lastPlayed: Value(DateTime.utc(2026, 10, 1)),
      ),
    ]);
    final first = _track('current', 'Current Song');
    final active = FakeActivePlayback()..emit(_playbackState(first));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          activePlaybackProvider.overrideWithValue(active),
        ],
        child: const MaterialApp(home: Scaffold(body: HomeScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recently played'), findsOneWidget);
    expect(
      tester
          .widget<SpotifinCollectionCard>(
            find.byType(SpotifinCollectionCard).first,
          )
          .title,
      'Current Song',
    );
    expect(find.text('Older Song'), findsWidgets);

    final next = _track('next', 'Next Song');
    active.emit(_playbackState(next, history: [first]));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SpotifinCollectionCard>(
            find.byType(SpotifinCollectionCard).first,
          )
          .title,
      'Next Song',
    );
    expect(find.text('Current Song'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('renders generated mixes as valid slivers', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 5000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.upsertTracks([
      for (var index = 0; index < 3; index++)
        TracksCompanion.insert(
          id: 'track-$index',
          name: 'Track $index',
          artist: const Value('Artist'),
          labels: const Value('["rock"]'),
        ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: Scaffold(body: HomeScreen())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Rock mix'), findsOneWidget);
    expect(find.text('Good listening'), findsNothing);
    expect(find.byType(SearchBar), findsOneWidget);
    expect(find.byTooltip('Save Rock mix as playlist'), findsOneWidget);
    expect(find.text('Playlists'), findsNothing);

    await database.replacePlaylists([
      PlaylistsCompanion.insert(
        id: 'playlist',
        name: 'Road trip',
        trackIds: const Value('["track-0","track-1","track-2"]'),
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Playlists'), findsOneWidget);
    expect(find.text('Road trip'), findsOneWidget);
    expect(find.byType(PlaylistArtwork), findsOneWidget);

    await _secondaryTap(tester, find.byType(TrackContextMenu).first);
    await tester.pumpAndSettle();
    expect(find.text('Delete permanently'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Delete permanently'),
        matching: find.byType(ListTile),
      ),
      findsNothing,
    );
    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();
    expect(find.text('Delete song permanently?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Save Rock mix as playlist'));
    await tester.pumpAndSettle();
    expect(find.text('Save mix as playlist'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).initialValue,
      'Rock mix',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(SearchBar), 'Track 1');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.byType(SearchBar), findsOneWidget);
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text('Recently added'), findsNothing);

    await tester.enterText(find.byType(SearchBar), 'Artist');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    await tester.tap(find.widgetWithText(Tab, 'Artists'));
    await tester.pump();

    expect(find.byType(SpotifinCollectionCard), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });

  testWidgets('horizontal track cards reveal the shared play button', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.upsertTracks([
      TracksCompanion.insert(
        id: 'track-0',
        name: 'Track 0',
        artist: const Value('Artist'),
        album: const Value('Album'),
        albumId: const Value('album-0'),
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: Scaffold(body: HomeScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('All songs'), findsOneWidget);
    expect(find.byType(SpotifinCollectionCard), findsWidgets);
    expect(find.byType(SpotifinPlayButton), findsNothing);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(
      tester.getCenter(find.byType(SpotifinCollectionCard).first),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SpotifinPlayButton), findsOneWidget);
    await gesture.removePointer();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });

  for (final searchArtist in [true, false]) {
    testWidgets(
      'search ${searchArtist ? 'artist albums' : 'albums'} include songs beyond the search limit',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 2000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final database = AppDatabase.forTesting(NativeDatabase.memory());
        await database.upsertTracks([
          for (var index = 0; index < 40; index++)
            TracksCompanion.insert(
              id: 'track-$index',
              name: 'Song ${index.toString().padLeft(2, '0')}',
              artist: const Value('zebrahead'),
              album: const Value('The Bonus Brothers'),
              albumId: const Value('bonus-brothers'),
            ),
        ]);
        final active = FakeActivePlayback();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWithValue(database),
              activePlaybackProvider.overrideWithValue(active),
            ],
            child: const MaterialApp(home: Scaffold(body: HomeScreen())),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField),
          searchArtist ? 'zebrahead' : 'The Bonus Brothers',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(SpotifinCollectionCard).first);
        await tester.pumpAndSettle();
        if (searchArtist) {
          await tester.tap(find.widgetWithText(Tab, 'Albums'));
          await tester.pumpAndSettle();
          final card = tester.widget<SpotifinCollectionCard>(
            find.byType(SpotifinCollectionCard),
          );
          expect(card.subtitle, '40 songs');
          await tester.tap(find.byType(SpotifinCollectionCard));
          await tester.pumpAndSettle();
        }
        expect(find.textContaining('40 songs'), findsOneWidget);
        await tester.tap(find.byType(SpotifinPlayButton));
        await tester.pumpAndSettle();
        final queued =
            active.actionArguments['replaceQueue']!.first as List<Track>;
        expect(queued, hasLength(40));
        expect(queued.map((track) => track.id), contains('track-39'));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        await tester.runAsync(database.close);
      },
    );
  }

  testWidgets('search album results keep artwork on the detail page', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.upsertTracks([
      TracksCompanion.insert(
        id: 'track-0',
        name: 'Song',
        artist: const Value('Artist'),
        album: const Value('Album'),
        albumId: const Value('album-0'),
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: const MaterialApp(home: Scaffold(body: HomeScreen())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(SearchBar), 'Album');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(find.byType(SpotifinCollectionCard), findsWidgets);
    await tester.tap(find.byType(SpotifinCollectionCard).first);
    await tester.pumpAndSettle();

    expect(find.text('ALBUM'), findsOneWidget);
    expect(find.text('Album'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });
}

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

Track _track(String id, String name) => Track(
  id: id,
  name: name,
  album: 'Album',
  albumId: 'album',
  artist: 'Artist',
  artistItems: '[]',
  labels: '',
  durationTicks: 0,
  container: '',
  favorite: false,
  playCount: 0,
);

ActivePlaybackState _playbackState(
  Track current, {
  List<Track> history = const [],
}) => ActivePlaybackState(
  destination: PlaybackDestination.local,
  track: current,
  index: 0,
  entryId: 'entry-${current.id}',
  queue: [current],
  upcoming: [current],
  upcomingOffset: 0,
  history: history,
  playing: true,
  position: Duration.zero,
  duration: Duration.zero,
  volumeSlider: 1,
  shuffle: false,
  repeatMode: LoopMode.off,
  busy: false,
  recovering: false,
  capabilities: PlaybackCapability.values.toSet(),
);
