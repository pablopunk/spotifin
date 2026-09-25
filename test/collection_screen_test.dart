import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/app/theme.dart';
import 'package:spotifin/features/common/artwork.dart';
import 'package:spotifin/features/common/design_system.dart';
import 'package:spotifin/features/common/playlist_artwork.dart';
import 'package:spotifin/features/library/collection_sort.dart';
import 'package:spotifin/features/library/library_screen.dart';
import 'package:spotifin/services/playback/playback_service.dart';
import 'package:spotifin/storage/database.dart';

class _MockPlayback extends Mock implements PlaybackService {}

class _FakeTrack extends Fake implements Track {}

PlaybackService _mockPlayback() {
  final playback = _MockPlayback();
  when(() => playback.addListener(any())).thenReturn(null);
  when(() => playback.removeListener(any())).thenReturn(null);
  when(() => playback.currentTrack).thenReturn(null);
  when(() => playback.playing).thenReturn(false);
  when(() => playback.shuffle).thenReturn(false);
  when(() => playback.toggle()).thenAnswer((_) async {});
  when(() => playback.replaceQueue(any(), shuffle: any(named: 'shuffle')))
      .thenAnswer((_) async {});
  when(() => playback.replaceQueue(any())).thenAnswer((_) async {});
  return playback;
}

Widget _appWithPlayback(
  Widget home,
  AppDatabase database,
  PlaybackService playback,
) => ProviderScope(
  overrides: [
    databaseProvider.overrideWithValue(database),
    playbackProvider.overrideWithValue(playback),
  ],
  child: MaterialApp(theme: buildTheme(), home: home),
);

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeTrack());
    registerFallbackValue(<Track>[]);
  });
  testWidgets('artist collections split songs and albums into tabs', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final tracks = await _tracks();

    await tester.pumpWidget(
      _app(
        CollectionScreen(
          title: 'Artist',
          kind: CollectionKind.artist,
          tracks: tracks.list,
        ),
        tracks.database,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(Tab, 'Songs'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Albums'), findsOneWidget);
    expect(find.text('First song'), findsOneWidget);
    expect(find.text('First album'), findsNothing);

    await tester.tap(find.widgetWithText(Tab, 'Albums'));
    await tester.pumpAndSettle();

    expect(find.byType(SpotifinCollectionCard), findsNWidgets(4));
    expect(find.text('First album'), findsOneWidget);
    expect(find.text('Second album'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _dispose(tester, tracks.database);
  });

  testWidgets('artist albums show full albums first, then by release date', (
    tester,
  ) async {
    final tracks = await _tracks();

    await tester.pumpWidget(
      _app(
        CollectionScreen(
          title: 'Artist',
          kind: CollectionKind.artist,
          tracks: tracks.list,
        ),
        tracks.database,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Albums'));
    await tester.pumpAndSettle();

    final titles = tester
        .widgetList<SpotifinCollectionCard>(
          find.byType(SpotifinCollectionCard, skipOffstage: false),
        )
        .map((card) => card.title)
        .toList();
    expect(titles, [
      'Long player',
      'Undated single',
      'First album',
      'Second album',
    ]);
    expect(find.text('Singles & EPs', skipOffstage: false), findsNothing);
    await _dispose(tester, tracks.database);
  });

  testWidgets('other collections stay a single list', (tester) async {
    final tracks = await _tracks();

    await tester.pumpWidget(
      _app(
        CollectionScreen(
          title: 'Album',
          kind: CollectionKind.album,
          tracks: tracks.list,
        ),
        tracks.database,
      ),
    );
    await tester.pump();

    expect(find.byType(Tab), findsNothing);
    expect(find.text('First song'), findsOneWidget);
    final scrollView = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    final bottomInset = scrollView.slivers.last as SliverToBoxAdapter;
    expect(
      (bottomInset.child! as SizedBox).height,
      SpotifinChromeInsets.fallbackBottom,
    );
    await _dispose(tester, tracks.database);
  });

  testWidgets('collection header offers an enabled shuffle toggle', (
    tester,
  ) async {
    final tracks = await _tracks();

    await tester.pumpWidget(
      _app(
        CollectionScreen(
          title: 'Album',
          kind: CollectionKind.album,
          tracks: tracks.list,
        ),
        tracks.database,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Shuffle'), findsOneWidget);
    final shuffle = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.shuffle_rounded),
    );
    expect(shuffle.onPressed, isNotNull);
    await _dispose(tester, tracks.database);
  });

  testWidgets('each kind renders its eyebrow and tab contract', (tester) async {
    final tracks = await _tracks();
    for (final entry in {
      CollectionKind.library: 'LIBRARY',
      CollectionKind.album: 'ALBUM',
      CollectionKind.artist: 'ARTIST',
      CollectionKind.playlist: 'PLAYLIST',
    }.entries) {
      await tester.pumpWidget(
        _app(
          CollectionScreen(
            title: 'Title',
            kind: entry.key,
            tracks: tracks.list,
          ),
          tracks.database,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      if (entry.key == CollectionKind.artist) {
        expect(find.widgetWithText(Tab, 'Songs'), findsOneWidget);
        expect(find.widgetWithText(Tab, 'Albums'), findsOneWidget);
      } else {
        expect(find.byType(Tab), findsNothing);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    }
    await tester.runAsync(tracks.database.close);
  });

  testWidgets('album headers derive artwork from the first track', (
    tester,
  ) async {
    final tracks = await _tracks();
    await tester.pumpWidget(
      _app(
        CollectionScreen(
          title: 'First album',
          kind: CollectionKind.album,
          tracks: tracks.list
              .where((track) => track.albumId == 'album-one')
              .toList(),
        ),
        tracks.database,
      ),
    );
    await tester.pumpAndSettle();

    final artwork = tester.widget<Artwork>(find.byType(Artwork).first);
    expect(artwork.itemId, 'album-one');
    expect(artwork.size, 160);
    await _dispose(tester, tracks.database);
  });

  testWidgets('playlist headers keep the mosaic artwork', (tester) async {
    final tracks = await _tracks();
    await tester.pumpWidget(
      _app(
        CollectionScreen(
          title: 'Mix',
          kind: CollectionKind.playlist,
          tracks: tracks.list,
          artwork: PlaylistArtwork(
            tracks: tracks.list,
            size: 160,
            borderRadius: SpotifinRadii.card,
          ),
        ),
        tracks.database,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PlaylistArtwork), findsOneWidget);
    await _dispose(tester, tracks.database);
  });

  testWidgets('playlist order is an icon beside the other header controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final tracks = await _tracks();
    await tester.pumpWidget(
      _app(
        CollectionScreen(
          title: 'Mix',
          kind: CollectionKind.playlist,
          tracks: tracks.list,
        ),
        tracks.database,
      ),
    );
    await tester.pumpAndSettle();

    final playY = tester.getCenter(find.byType(SpotifinPlayButton)).dy;
    expect(tester.getCenter(find.byTooltip('Shuffle')).dy, playY);
    expect(tester.getCenter(find.byTooltip('Sort collection songs')).dy, playY);
    final controls = find
        .ancestor(
          of: find.byTooltip('Sort collection songs'),
          matching: find.byType(Row),
        )
        .first;
    expect(
      tester
          .getCenter(
            find.descendant(
              of: controls,
              matching: find.byTooltip('Coverflow'),
            ),
          )
          .dy,
      playY,
    );
    expect(find.text('Sort by'), findsNothing);

    await tester.tap(find.byTooltip('Sort collection songs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Title A–Z').last);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CollectionScreen)),
    );
    expect(container.read(collectionTrackSortProvider), TrackSort.nameAsc);
    await _dispose(tester, tracks.database);
  });

  testWidgets('artist order icon follows the selected tab', (tester) async {
    final tracks = await _tracks();
    await tester.pumpWidget(
      _app(
        CollectionScreen(
          title: 'Artist',
          kind: CollectionKind.artist,
          tracks: tracks.list,
        ),
        tracks.database,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Sort collection songs'), findsOneWidget);
    await tester.tap(find.widgetWithText(Tab, 'Albums'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Sort artist albums'), findsOneWidget);
    expect(find.byTooltip('Sort collection songs'), findsNothing);
    expect(find.text('Sort by'), findsNothing);

    await _dispose(tester, tracks.database);
  });

  testWidgets('album metadata shows artist, year, count, and duration', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.upsertTracks([
      TracksCompanion.insert(
        id: 'a1',
        name: 'One',
        artist: const Value('Artist'),
        album: const Value('Album'),
        albumId: const Value('album-x'),
        durationTicks: const Value(180 * 10000000),
        premiereDate: Value(DateTime(2024, 3, 1)),
      ),
      TracksCompanion.insert(
        id: 'a2',
        name: 'Two',
        artist: const Value('Artist'),
        album: const Value('Album'),
        albumId: const Value('album-x'),
        durationTicks: const Value(180 * 10000000),
        premiereDate: Value(DateTime(2024, 3, 1)),
      ),
    ]);
    final list = await database.allTracks();

    await tester.pumpWidget(
      _app(
        CollectionScreen(
          title: 'Album',
          kind: CollectionKind.album,
          tracks: list,
        ),
        database,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Artist • 2024 • 2 songs • 6 min'), findsOneWidget);
    await _dispose(tester, database);
  });

  testWidgets('album-level dates win over track dates', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.upsertTracks([
      TracksCompanion.insert(
        id: 'a1',
        name: 'One',
        artist: const Value('Artist'),
        album: const Value('Album'),
        albumId: const Value('album-x'),
        durationTicks: const Value(60 * 10000000),
        premiereDate: Value(DateTime(2019, 6, 1)),
      ),
    ]);
    await database.replaceAlbumDates([
      AlbumDatesCompanion.insert(
        albumId: 'album-x',
        premiereDate: DateTime(2024, 5, 1),
      ),
    ]);
    final list = await database.allTracks();

    await tester.pumpWidget(
      _app(
        CollectionScreen(
          title: 'Album',
          kind: CollectionKind.album,
          tracks: list,
        ),
        database,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('2024'), findsOneWidget);
    expect(find.textContaining('2019'), findsNothing);
    await _dispose(tester, database);
  });

  testWidgets('mixed album artists show Various artists', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.upsertTracks([
      TracksCompanion.insert(
        id: 'a1',
        name: 'One',
        artist: const Value('Ann'),
        album: const Value('Album'),
        durationTicks: const Value(60 * 10000000),
      ),
      TracksCompanion.insert(
        id: 'a2',
        name: 'Two',
        artist: const Value('Bob'),
        album: const Value('Album'),
        durationTicks: const Value(60 * 10000000),
      ),
    ]);
    final list = await database.allTracks();

    await tester.pumpWidget(
      _app(
        CollectionScreen(
          title: 'Album',
          kind: CollectionKind.album,
          tracks: list,
        ),
        database,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Various artists'), findsOneWidget);
    await _dispose(tester, database);
  });

  testWidgets('artist metadata omits performer and year', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.upsertTracks([
      TracksCompanion.insert(
        id: 'a1',
        name: 'One',
        artist: const Value('Artist'),
        durationTicks: const Value(60 * 10000000),
      ),
      TracksCompanion.insert(
        id: 'a2',
        name: 'Two',
        artist: const Value('Artist'),
        durationTicks: const Value(60 * 10000000),
      ),
    ]);
    final list = await database.allTracks();

    await tester.pumpWidget(
      _app(
        CollectionScreen(
          title: 'Artist',
          kind: CollectionKind.artist,
          tracks: list,
        ),
        database,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 songs • 2 min'), findsOneWidget);
    await _dispose(tester, database);
  });

  testWidgets('duration edge cases format without extra separators', (
    tester,
  ) async {
    final cases = {
      'zero omits duration': (ticks: [0, 0], expected: '2 songs'),
      'singular song': (ticks: [60 * 10000000], expected: '1 song • 1 min'),
      'exact hour omits minutes': (
        ticks: [3600 * 10000000],
        expected: '1 song • 1 hr',
      ),
      'hour and minutes': (
        ticks: [3600 * 10000000, 720 * 10000000],
        expected: '2 songs • 1 hr 12 min',
      ),
    };
    for (final entry in cases.entries) {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      await database.upsertTracks([
        for (var i = 0; i < entry.value.ticks.length; i++)
          TracksCompanion.insert(
            id: 't$i',
            name: 'Song $i',
            artist: const Value('Artist'),
            durationTicks: Value(entry.value.ticks[i]),
          ),
      ]);
      final list = await database.allTracks();
      await tester.pumpWidget(
        _appWithPlayback(
          CollectionScreen(
            title: 'Playlist',
            kind: CollectionKind.playlist,
            tracks: list,
          ),
          database,
          _mockPlayback(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(entry.value.expected),
        findsOneWidget,
        reason: entry.key,
      );
      await _dispose(tester, database);
    }
  });

  testWidgets('long headers fit narrow viewports', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.upsertTracks([
      TracksCompanion.insert(
        id: 'a1',
        name: 'One',
        artist: const Value(
          'A very long artist name that keeps going and going',
        ),
        album: const Value('Album'),
        durationTicks: const Value(60 * 10000000),
      ),
    ]);
    final list = await database.allTracks();

    await tester.pumpWidget(
      _app(
        CollectionScreen(
          title:
              'A very long album title that should ellipsize instead of '
              'overflowing the narrow viewport',
          kind: CollectionKind.album,
          tracks: list,
        ),
        database,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ALBUM'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _dispose(tester, database);
  });
}

Future<void> _dispose(WidgetTester tester, AppDatabase database) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
  await tester.runAsync(database.close);
}

Widget _app(Widget home, AppDatabase database) => ProviderScope(
  overrides: [databaseProvider.overrideWithValue(database)],
  child: MaterialApp(theme: buildTheme(), home: home),
);

Future<({AppDatabase database, List<Track> list})> _tracks() async {
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  await database.upsertTracks([
    TracksCompanion.insert(
      id: 'one',
      name: 'First song',
      artist: const Value('Artist'),
      album: const Value('First album'),
      albumId: const Value('album-one'),
      premiereDate: Value(DateTime(2024, 3, 1)),
    ),
    TracksCompanion.insert(
      id: 'two',
      name: 'Second song',
      artist: const Value('Artist'),
      album: const Value('First album'),
      albumId: const Value('album-one'),
      premiereDate: Value(DateTime(2024, 3, 1)),
    ),
    TracksCompanion.insert(
      id: 'three',
      name: 'Third song',
      artist: const Value('Artist'),
      album: const Value('Second album'),
      albumId: const Value('album-two'),
      premiereDate: Value(DateTime(2019, 6, 1)),
    ),
    TracksCompanion.insert(
      id: 'four',
      name: 'Fourth song',
      artist: const Value('Artist'),
      album: const Value('Undated single'),
      albumId: const Value('album-four'),
    ),
    for (var index = 0; index < 6; index++)
      TracksCompanion.insert(
        id: 'long-$index',
        name: 'Long song $index',
        artist: const Value('Artist'),
        album: const Value('Long player'),
        albumId: const Value('album-three'),
        premiereDate: Value(DateTime(2016, 9, 1)),
      ),
  ]);
  await database.replaceAlbumDates([
    AlbumDatesCompanion.insert(
      albumId: 'album-four',
      premiereDate: DateTime(2025, 2, 1),
    ),
  ]);
  return (database: database, list: await database.allTracks());
}
