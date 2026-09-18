import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/app/theme.dart';
import 'package:spotifin/features/common/design_system.dart';
import 'package:spotifin/features/common/playlist_artwork.dart';
import 'package:spotifin/features/coverflow/coverflow_controller.dart';
import 'package:spotifin/features/library/library_screen.dart';
import 'package:spotifin/storage/database.dart';

void main() {
  testWidgets('mobile Coverflow follows the selected library tab', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.upsertTracks([
      TracksCompanion.insert(
        id: 'one',
        name: 'First song',
        artist: const Value('Artist'),
        album: const Value('Selected album'),
        albumId: const Value('selected-album'),
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
    await tester.pump(const Duration(seconds: 1));
    expect(
      container
          .read(mobileCoverflowCollectionProvider)
          .active
          ?.items
          .single
          .title,
      'First song',
    );

    await tester.tap(find.widgetWithText(Tab, 'Albums'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final collection = container.read(mobileCoverflowCollectionProvider).active;
    expect(collection?.items.single.title, 'Selected album');
    expect(collection?.playback, MobileCoverflowPlayback.collection);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    container.dispose();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });

  testWidgets('library shows the library header above its tabs', (
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

    expect(find.text('LIBRARY'), findsOneWidget);
    expect(find.text('Your library'), findsWidgets);
    expect(find.text('1 song'), findsOneWidget);
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

  testWidgets('artist cards keep multi-artist songs apart', (tester) async {
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
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp(theme: buildTheme(), home: const LibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Artists'));
    await tester.pumpAndSettle();

    expect(find.text('Lia Kali'), findsOneWidget);
    expect(find.text('Toni Anzis'), findsOneWidget);
    expect(find.text('2 songs'), findsNWidgets(2));
    expect(find.text('1 songs'), findsOneWidget);

    await tester.tap(find.text('Toni Anzis'));
    await tester.pumpAndSettle();

    expect(find.text('Cantaré'), findsOneWidget);
    expect(find.text('Otra'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });

  testWidgets('album cards reveal direct play on hover', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.upsertTracks([
      TracksCompanion.insert(
        id: 'one',
        name: 'First song',
        artist: const Value('Artist'),
        album: const Value('Album'),
        albumId: const Value('album-one'),
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp(theme: buildTheme(), home: const LibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Albums'));
    await tester.pumpAndSettle();

    expect(find.byType(SpotifinCollectionCard), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SpotifinCollectionCard),
        matching: find.byType(SpotifinPlayButton),
      ),
      findsNothing,
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.byType(SpotifinCollectionCard)));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(SpotifinCollectionCard),
        matching: find.byType(SpotifinPlayButton),
      ),
      findsOneWidget,
    );
    await gesture.removePointer();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });

  testWidgets('empty playlists do not expose an enabled play control', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.upsertTracks([
      TracksCompanion.insert(
        id: 'one',
        name: 'First song',
        artist: const Value('Artist'),
      ),
    ]);
    await database.replacePlaylists([
      PlaylistsCompanion.insert(
        id: 'empty',
        name: 'Empty mix',
        trackIds: const Value('[]'),
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp(theme: buildTheme(), home: const LibraryScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Playlists'));
    await tester.pumpAndSettle();

    expect(find.text('Empty mix'), findsOneWidget);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.byType(SpotifinCollectionCard)));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(SpotifinCollectionCard),
        matching: find.byType(SpotifinPlayButton),
      ),
      findsNothing,
    );
    await gesture.removePointer();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });
}
