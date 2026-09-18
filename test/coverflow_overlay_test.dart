import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/app/theme.dart';
import 'package:spotifin/features/common/design_system.dart';
import 'package:spotifin/features/coverflow/coverflow_overlay.dart';
import 'package:spotifin/features/coverflow/coverflow_stage.dart';
import 'package:spotifin/services/playback/playback_service.dart';
import 'package:spotifin/storage/database.dart';

class _MockPlayback extends Mock implements PlaybackService {}

class _FakeTrack extends Fake implements Track {}

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

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeTrack());
    registerFallbackValue(<Track>[]);
    registerFallbackValue(Duration.zero);
  });

  testWidgets('overlay fills the viewport with a compact playback pill', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final playback = _MockPlayback();
    final queue = [_track('1', 'First'), _track('2', 'Second')];
    when(() => playback.addListener(any())).thenReturn(null);
    when(() => playback.removeListener(any())).thenReturn(null);
    when(() => playback.queue).thenReturn(queue);
    when(() => playback.currentIndex).thenReturn(0);
    when(() => playback.currentTrack).thenReturn(queue.first);
    when(() => playback.playing).thenReturn(false);

    var dismissed = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          playbackProvider.overrideWithValue(playback),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: CoverflowOverlay(onDismiss: () => dismissed = true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cover Flow'), findsNothing);
    expect(find.text('First'), findsWidgets);
    expect(find.byType(SpotifinPlayButton), findsOneWidget);
    expect(find.byTooltip('Previous'), findsNothing);
    expect(find.byTooltip('Next'), findsNothing);
    expect(find.byTooltip('Dismiss'), findsOneWidget);

    await tester.fling(find.byType(CoverflowStage), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(dismissed, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });

  testWidgets('overlay falls back to library when queue is empty', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.upsertTracks([
      TracksCompanion.insert(
        id: 'one',
        name: 'Lonely song',
        artist: const Value('Artist'),
        album: const Value('Album'),
      ),
    ]);
    final playback = _MockPlayback();
    when(() => playback.addListener(any())).thenReturn(null);
    when(() => playback.removeListener(any())).thenReturn(null);
    when(() => playback.queue).thenReturn(const <Track>[]);
    when(
      () => playback.replaceQueue(any(), startIndex: any(named: 'startIndex')),
    ).thenAnswer((_) async {});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          playbackProvider.overrideWithValue(playback),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(body: CoverflowOverlay(onDismiss: () {})),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lonely song'), findsWidgets);
    expect(find.byTooltip('Previous'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });
}
