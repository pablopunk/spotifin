import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/app/theme.dart';
import 'package:spotifin/features/common/design_system.dart';
import 'package:spotifin/features/coverflow/coverflow_model.dart';
import 'package:spotifin/features/library/collection_sort.dart';
import 'package:spotifin/features/library/library_screen.dart';
import 'package:spotifin/storage/database.dart';

Track _track(
  String id,
  String name, {
  String artist = 'Artist',
  String album = 'Album',
  int durationTicks = 0,
  DateTime? dateCreated,
}) => Track(
  id: id,
  name: name,
  album: album,
  artist: artist,
  artistItems: '[]',
  labels: '[]',
  durationTicks: durationTicks,
  container: 'mp3',
  favorite: false,
  playCount: 0,
  dateCreated: dateCreated,
);

void main() {
  test('collection entries sort by name both ways', () {
    final entries = [
      MapEntry('Beta', [_track('1', 'B')]),
      MapEntry('alpha', [_track('2', 'A')]),
    ];
    expect(
      sortCollectionEntries(entries, CollectionSort.nameAsc).map((e) => e.key),
      ['alpha', 'Beta'],
    );
    expect(
      sortCollectionEntries(entries, CollectionSort.nameDesc).map((e) => e.key),
      ['Beta', 'alpha'],
    );
  });

  test('collection entries sort by song count with name tie-break', () {
    final entries = [
      MapEntry('Beta', [_track('1', 'B')]),
      MapEntry('alpha', [_track('2', 'A'), _track('3', 'C')]),
      MapEntry('Gamma', [_track('4', 'D'), _track('5', 'E')]),
    ];
    expect(
      sortCollectionEntries(
        entries,
        CollectionSort.mostSongs,
      ).map((e) => e.key),
      ['alpha', 'Gamma', 'Beta'],
    );
    expect(
      sortCollectionEntries(
        entries,
        CollectionSort.fewestSongs,
      ).map((e) => e.key),
      ['Beta', 'alpha', 'Gamma'],
    );
  });

  test('tracks sort by title, artist, duration, and recency', () {
    final tracks = [
      _track('1', 'Beta', artist: 'Zed', durationTicks: 10),
      _track(
        '2',
        'alpha',
        artist: 'Amy',
        durationTicks: 30,
        dateCreated: DateTime(2024, 1, 1),
      ),
      _track(
        '3',
        'Gamma',
        artist: 'Amy',
        durationTicks: 20,
        dateCreated: DateTime(2025, 1, 1),
      ),
    ];
    expect(
      sortTracks(tracks, TrackSort.defaultOrder).map((t) => t.id),
      ['1', '2', '3'],
    );
    expect(
      sortTracks(tracks, TrackSort.nameAsc).map((t) => t.name),
      ['alpha', 'Beta', 'Gamma'],
    );
    expect(
      sortTracks(tracks, TrackSort.artistAsc).map((t) => t.id),
      ['2', '3', '1'],
    );
    expect(
      sortTracks(tracks, TrackSort.longestFirst).map((t) => t.id),
      ['2', '3', '1'],
    );
    expect(
      sortTracks(tracks, TrackSort.shortestFirst).map((t) => t.id),
      ['1', '3', '2'],
    );
    expect(
      sortTracks(tracks, TrackSort.recentlyAdded).map((t) => t.id),
      ['3', '2', '1'],
    );
  });

  test('playlists sort by name and song count', () {
    const playlists = [
      Playlist(id: 'b', name: 'Beta', trackIds: '[]'),
      Playlist(id: 'a', name: 'alpha', trackIds: '[]'),
    ];
    final byId = {
      'b': [_track('1', 'One')],
      'a': [_track('2', 'Two'), _track('3', 'Three')],
    };
    expect(
      sortPlaylists(playlists, byId, CollectionSort.nameAsc).map((p) => p.id),
      ['a', 'b'],
    );
    expect(
      sortPlaylists(playlists, byId, CollectionSort.mostSongs).map((p) => p.id),
      ['a', 'b'],
    );
    expect(
      sortPlaylists(
        playlists,
        byId,
        CollectionSort.fewestSongs,
      ).map((p) => p.id),
      ['b', 'a'],
    );
  });

  test('coverflow collections follow the grid sort', () {
    final items = [
      const CoverflowItem(
        id: 'a',
        title: 'Beta',
        subtitle: '1 song',
        artItemId: 'a',
        tracks: [],
        collection: true,
      ),
      CoverflowItem(
        id: 'b',
        title: 'alpha',
        subtitle: '2 songs',
        artItemId: 'b',
        tracks: [_track('1', 'One'), _track('2', 'Two')],
        collection: true,
      ),
    ];
    expect(
      sortCoverflowCollections(items, CollectionSort.mostSongs).map(
        (item) => item.title,
      ),
      ['alpha', 'Beta'],
    );
    expect(
      sortCoverflowCollections(items, CollectionSort.nameDesc).map(
        (item) => item.title,
      ),
      ['Beta', 'alpha'],
    );
  });

  testWidgets('library albums grid can order by song count', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.upsertTracks([
      TracksCompanion.insert(
        id: 'a1',
        name: 'A song',
        artist: const Value('Artist'),
        album: const Value('Zebra album'),
        albumId: const Value('zebra'),
      ),
      TracksCompanion.insert(
        id: 'b1',
        name: 'B song one',
        artist: const Value('Artist'),
        album: const Value('Alpha album'),
        albumId: const Value('alpha'),
      ),
      TracksCompanion.insert(
        id: 'b2',
        name: 'B song two',
        artist: const Value('Artist'),
        album: const Value('Alpha album'),
        albumId: const Value('alpha'),
      ),
    ]);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildTheme(), home: const LibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Albums'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Sort albums'), findsOneWidget);
    var titles = tester
        .widgetList<SpotifinCollectionCard>(find.byType(SpotifinCollectionCard))
        .map((card) => card.title)
        .toList();
    expect(titles, ['Alpha album', 'Zebra album']);

    container.read(libraryAlbumSortProvider.notifier).state =
        CollectionSort.fewestSongs;
    await tester.pumpAndSettle();
    titles = tester
        .widgetList<SpotifinCollectionCard>(find.byType(SpotifinCollectionCard))
        .map((card) => card.title)
        .toList();
    expect(titles, ['Zebra album', 'Alpha album']);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    container.dispose();
    await tester.runAsync(database.close);
  });

  testWidgets('library artists grid can order by song count', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.upsertTracks([
      TracksCompanion.insert(
        id: 'a1',
        name: 'Solo',
        artist: const Value('Zebra'),
        artistItems: const Value('[{"id":"zebra","name":"Zebra"}]'),
      ),
      TracksCompanion.insert(
        id: 'b1',
        name: 'Duo one',
        artist: const Value('Alpha'),
        artistItems: const Value('[{"id":"alpha","name":"Alpha"}]'),
      ),
      TracksCompanion.insert(
        id: 'b2',
        name: 'Duo two',
        artist: const Value('Alpha'),
        artistItems: const Value('[{"id":"alpha","name":"Alpha"}]'),
      ),
    ]);
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildTheme(), home: const LibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Artists'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Sort artists'), findsOneWidget);
    container.read(libraryArtistSortProvider.notifier).state =
        CollectionSort.mostSongs;
    await tester.pumpAndSettle();

    final titles = tester
        .widgetList<SpotifinCollectionCard>(find.byType(SpotifinCollectionCard))
        .map((card) => card.title)
        .toList();
    expect(titles.first, 'Alpha');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    container.dispose();
    await tester.runAsync(database.close);
  });
}
