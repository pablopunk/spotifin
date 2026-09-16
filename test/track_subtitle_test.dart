import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/app/theme.dart';
import 'package:spotifin/features/common/track_tile.dart';
import 'package:spotifin/storage/database.dart';

void main() {
  testWidgets('tapping an artist in a track row opens only their songs', (
    tester,
  ) async {
    final database = await _database();
    final cantare = (await database.allTracks()).firstWhere(
      (track) => track.id == 'cantare',
    );

    await _pump(tester, database, cantare);
    await tester.tapOnText(find.textRange.ofSubstring('Lia Kali'));
    await tester.pumpAndSettle();

    expect(find.text('Cantaré'), findsWidgets);
    expect(find.text('Otra'), findsOneWidget);
    expect(find.text('Toni Solo'), findsNothing);

    await _close(tester, database);
  });

  testWidgets('a combined artist item still splits into tappable names', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.upsertTracks([
      TracksCompanion.insert(
        id: 'combined',
        name: 'Combined song',
        artist: const Value('Lia Kali, Toni Anzis'),
        artistItems: const Value(
          '[{"id":"combined","name":"Lia Kali, Toni Anzis"}]',
        ),
        album: const Value('Kaelis'),
      ),
    ]);
    final track = (await database.allTracks()).single;

    await _pump(tester, database, track);
    await tester.tapOnText(find.textRange.ofSubstring('Toni Anzis'));
    await tester.pumpAndSettle();

    expect(find.text('Combined song'), findsWidgets);

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
      album: const Value('Kaelis'),
    ),
    TracksCompanion.insert(
      id: 'otra',
      name: 'Otra',
      artist: const Value('Lia Kali'),
      artistItems: const Value('[{"id":"lia","name":"Lia Kali"}]'),
      album: const Value('Kaelis'),
    ),
    TracksCompanion.insert(
      id: 'toni-solo',
      name: 'Toni Solo',
      artist: const Value('Toni Anzis'),
      artistItems: const Value('[{"id":"toni","name":"Toni Anzis"}]'),
      album: const Value('Solo'),
    ),
  ]);
  return database;
}

Future<void> _pump(WidgetTester tester, AppDatabase database, Track track) =>
    tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: TrackTile(track: track, contextTracks: [track]),
          ),
        ),
      ),
    );

Future<void> _close(WidgetTester tester, AppDatabase database) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
  await tester.runAsync(database.close);
}
