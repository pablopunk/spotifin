import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/app/theme.dart';
import 'package:spotifin/features/common/design_system.dart';
import 'package:spotifin/features/common/playlist_artwork.dart';
import 'package:spotifin/features/library/library_screen.dart';
import 'package:spotifin/storage/database.dart';

void main() {
  testWidgets('library shows the collection header above its tabs', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.upsertTracks([
      TracksCompanion.insert(
        id: 'one',
        name: 'First song',
        artist: const Value('Artist'),
        album: const Value('Album'),
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp(theme: buildTheme(), home: const LibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('COLLECTION'), findsOneWidget);
    expect(find.text('Your library'), findsWidgets);
    expect(find.byType(SpotifinCountLabel), findsOneWidget);
    expect(find.byType(PlaylistArtwork), findsOneWidget);

    final play = tester.widget<SpotifinPlayButton>(
      find.byType(SpotifinPlayButton),
    );
    expect(play.onPressed, isNotNull);
    final shuffle = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.shuffle_rounded),
    );
    expect(shuffle.onPressed, isNotNull);

    for (final label in ['Songs', 'Albums', 'Artists', 'Playlists']) {
      expect(find.widgetWithText(Tab, label), findsOneWidget);
    }
    expect(find.text('First song'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });
}
