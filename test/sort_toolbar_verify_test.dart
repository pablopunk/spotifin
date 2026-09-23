import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/app/theme.dart';
import 'package:spotifin/features/library/collection_sort.dart';
import 'package:spotifin/features/library/library_screen.dart';
import 'package:spotifin/storage/database.dart';

void main() {
  testWidgets('toolbar sort menu changes library song order', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.upsertTracks([
      TracksCompanion.insert(id: 'b', name: 'Beta', artist: const Value('Zed')),
      TracksCompanion.insert(id: 'a', name: 'alpha', artist: const Value('Amy')),
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
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // Sort control lives in the top header toolbar next to coverflow.
    expect(find.byTooltip('Sort songs'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Wrap),
        matching: find.byTooltip('Sort songs'),
      ),
      findsOneWidget,
    );

    // Default order preserved.
    expect(container.read(libraryTrackSortProvider), TrackSort.defaultOrder);

    // Open the compact menu and pick Title A-Z.
    await tester.tap(find.byTooltip('Sort songs'));
    await tester.pumpAndSettle();
    expect(find.text('Title A–Z'), findsWidgets);
    await tester.tap(find.text('Title A–Z').last);
    await tester.pumpAndSettle();
    expect(container.read(libraryTrackSortProvider), TrackSort.nameAsc);
    expect(find.text('alpha'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    container.dispose();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });
}
