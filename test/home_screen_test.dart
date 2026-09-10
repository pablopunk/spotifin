import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/features/home/home_screen.dart';
import 'package:spotifin/storage/database.dart';

void main() {
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
          labels: Value(index == 0 ? '["rock"]' : '[]'),
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
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });
}
