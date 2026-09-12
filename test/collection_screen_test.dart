import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/app/theme.dart';
import 'package:spotifin/features/common/design_system.dart';
import 'package:spotifin/features/library/library_screen.dart';
import 'package:spotifin/storage/database.dart';

void main() {
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
          icon: Icons.person_rounded,
          artist: true,
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

    expect(find.byType(SpotifinCollectionCard), findsNWidgets(3));
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
          icon: Icons.person_rounded,
          artist: true,
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
    expect(titles, ['Long player', 'First album', 'Second album']);
    expect(find.text('Singles & EPs', skipOffstage: false), findsNothing);
    await _dispose(tester, tracks.database);
  });

  testWidgets('other collections stay a single list', (tester) async {
    final tracks = await _tracks();

    await tester.pumpWidget(
      _app(
        CollectionScreen(
          title: 'Album',
          icon: Icons.album_rounded,
          tracks: tracks.list,
        ),
        tracks.database,
      ),
    );
    await tester.pump();

    expect(find.byType(Tab), findsNothing);
    expect(find.text('First song'), findsOneWidget);
    await _dispose(tester, tracks.database);
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
  return (database: database, list: await database.allTracks());
}
