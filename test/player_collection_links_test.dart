import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/app/theme.dart';
import 'package:spotifin/features/common/artwork.dart';
import 'package:spotifin/features/player/player_collection_links.dart';
import 'package:spotifin/storage/database.dart';

void main() {
  testWidgets('tapping the first artist opens only their songs', (
    tester,
  ) async {
    final database = await _database();
    final cantare = await _cantare(database);

    await _pump(tester, database, cantare);
    await tester.tapOnText(find.textRange.ofSubstring('Lia Kali'));
    await tester.pumpAndSettle();

    expect(find.text('Cantaré'), findsOneWidget);
    expect(find.text('Otra'), findsOneWidget);
    expect(find.text('Toni Solo'), findsNothing);

    await _close(tester, database);
  });

  testWidgets('tapping the featured artist opens only their songs', (
    tester,
  ) async {
    final database = await _database();
    final cantare = await _cantare(database);

    await _pump(tester, database, cantare);
    await tester.tapOnText(find.textRange.ofSubstring('Toni Anzis'));
    await tester.pumpAndSettle();

    expect(find.text('Toni Solo'), findsOneWidget);
    expect(find.text('Cantaré'), findsOneWidget);
    expect(find.text('Otra'), findsNothing);

    await _close(tester, database);
  });

  testWidgets('artist links open an ARTIST page with artwork', (tester) async {
    final database = await _database();
    final cantare = await _cantare(database);

    await _pump(tester, database, cantare);
    await tester.tapOnText(find.textRange.ofSubstring('Lia Kali'));
    await tester.pumpAndSettle();

    expect(find.text('ARTIST'), findsOneWidget);
    expect(find.byType(Artwork), findsWidgets);

    await _close(tester, database);
  });
}

Future<AppDatabase> _database() async {
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  await database.upsertTracks([
    TracksCompanion.insert(
      id: 'cantare',
      name: 'Cantaré',
      artist: const Value('Lia Kali, Toni Anzis'),
      artistItems: const Value(
        '[{"id":"lia","name":"Lia Kali"},{"id":"toni","name":"Toni Anzis"}]',
      ),
    ),
    TracksCompanion.insert(
      id: 'otra',
      name: 'Otra',
      artist: const Value('Lia Kali'),
      artistItems: const Value('[{"id":"lia","name":"Lia Kali"}]'),
    ),
    TracksCompanion.insert(
      id: 'toni-solo',
      name: 'Toni Solo',
      artist: const Value('Toni Anzis'),
      artistItems: const Value('[{"id":"toni","name":"Toni Anzis"}]'),
    ),
  ]);
  return database;
}

Future<Track> _cantare(AppDatabase database) async =>
    (await database.allTracks()).firstWhere((track) => track.id == 'cantare');

Future<void> _pump(WidgetTester tester, AppDatabase database, Track track) =>
    tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: PlayerCollectionLinks(
              track: track,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ),
      ),
    );

Future<void> _close(WidgetTester tester, AppDatabase database) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
  await tester.runAsync(database.close);
}
