import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/app/theme.dart';
import 'package:spotifin/features/coverflow/coverflow_controller.dart';
import 'package:spotifin/features/coverflow/coverflow_header_toggle.dart';
import 'package:spotifin/features/coverflow/coverflow_model.dart';
import 'package:spotifin/features/coverflow/coverflow_overlay.dart';
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

  test('button request defaults to queue (null)', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(mobileCoverflowRequestedProvider), isNull);
  });

  testWidgets('rotation launch opens the queue, not the active view', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final playback = _MockPlayback();
    final queued = [
      _track('queue-1', 'Queued first'),
      _track('queue-2', 'Queued second'),
    ];
    when(() => playback.addListener(any())).thenReturn(null);
    when(() => playback.removeListener(any())).thenReturn(null);
    when(() => playback.queue).thenReturn(queued);
    when(() => playback.currentIndex).thenReturn(0);
    when(() => playback.currentTrack).thenReturn(queued.first);
    when(() => playback.playing).thenReturn(false);
    when(() => playback.toggle()).thenAnswer((_) async {});

    // A library/view collection exists, but rotation must ignore it: the
    // rotation path passes no collection, so the overlay falls back to the
    // queue. The registry check documents that the view was available.
    final registryContainer = ProviderContainer();
    addTearDown(registryContainer.dispose);
    final viewTrack = _track('view-1', 'View song');
    registryContainer
        .read(mobileCoverflowCollectionProvider)
        .register(
          Object(),
          MobileCoverflowCollection(
            items: trackCoverflowItems([viewTrack]),
            contextTracks: [viewTrack],
            playback: MobileCoverflowPlayback.tracks,
          ).forView('library:tracks'),
        );
    expect(
      registryContainer
          .read(mobileCoverflowCollectionProvider)
          .active
          ?.items
          .single
          .title,
      'View song',
    );
    expect(registryContainer.read(mobileCoverflowRequestedProvider), isNull);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          playbackProvider.overrideWithValue(playback),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: const Scaffold(body: CoverflowOverlay(onDismiss: _noop)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Queued first'), findsWidgets);
    expect(find.textContaining('View song'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });

  testWidgets('button launch snapshots the active view collection', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final viewTrack = _track('view-1', 'View song');
    final active = MobileCoverflowCollection(
      items: trackCoverflowItems([viewTrack]),
      contextTracks: [viewTrack],
      playback: MobileCoverflowPlayback.tracks,
    ).forView('library:tracks');
    container
        .read(mobileCoverflowCollectionProvider)
        .register(Object(), active);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: Size(600, 400)),
            child: Scaffold(
              body: CoverflowToggleButton(viewId: 'library:tracks'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(CoverflowToggleButton));
    await tester.pump();

    final requested = container.read(mobileCoverflowRequestedProvider);
    expect(requested, isNotNull);
    expect(requested?.viewId, 'library:tracks');
    expect(requested?.items.single.title, 'View song');
    expect(container.read(mobileCoverflowDismissedProvider), isFalse);
  });

  testWidgets('button collection overlay keeps view content over the queue', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final playback = _MockPlayback();
    final queued = [_track('queue-1', 'Queued song')];
    final albumTrack = _track('album-track', 'Album song');
    when(() => playback.addListener(any())).thenReturn(null);
    when(() => playback.removeListener(any())).thenReturn(null);
    when(() => playback.queue).thenReturn(queued);
    when(() => playback.currentTrack).thenReturn(queued.first);
    when(() => playback.playing).thenReturn(false);
    when(() => playback.playTrack(any(), any())).thenAnswer((_) async {});

    final requested = MobileCoverflowCollection(
      items: [
        CoverflowItem(
          id: 'album:selected',
          title: 'Selected album',
          subtitle: '1 song',
          artItemId: 'album',
          tracks: [albumTrack],
          collection: true,
        ),
      ],
      contextTracks: [albumTrack],
      playback: MobileCoverflowPlayback.collection,
    ).forView('library:albums');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          playbackProvider.overrideWithValue(playback),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: CoverflowOverlay(onDismiss: () {}, collection: requested),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Button path shows the view collection even though a queue exists.
    expect(find.textContaining('Selected album'), findsWidgets);
    expect(find.textContaining('Queued song'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });

  testWidgets('switching launch paths preserves queue order and position', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final playback = _MockPlayback();
    final queue = [
      _track('q1', 'Queue one'),
      _track('q2', 'Queue two'),
      _track('q3', 'Queue three'),
    ];
    when(() => playback.addListener(any())).thenReturn(null);
    when(() => playback.removeListener(any())).thenReturn(null);
    when(() => playback.queue).thenReturn(queue);
    when(() => playback.currentIndex).thenReturn(1);
    when(() => playback.currentTrack).thenReturn(queue[1]);
    when(() => playback.playing).thenReturn(true);
    when(() => playback.toggle()).thenAnswer((_) async {});
    when(() => playback.playQueueIndex(any())).thenAnswer((_) async {});
    when(() => playback.playTrack(any(), any())).thenAnswer((_) async {});

    // Rotation path: queue overlay.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          playbackProvider.overrideWithValue(playback),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: const Scaffold(body: CoverflowOverlay(onDismiss: _noop)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Queue two'), findsWidgets);

    // Button path: view collection overlay.
    final albumTrack = _track('album-1', 'Album song');
    final requested = MobileCoverflowCollection(
      items: [
        CoverflowItem(
          id: 'album:one',
          title: 'View album',
          subtitle: '1 song',
          artItemId: 'album',
          tracks: [albumTrack],
          collection: true,
        ),
      ],
      contextTracks: [albumTrack],
      playback: MobileCoverflowPlayback.collection,
    ).forView('library:albums');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          playbackProvider.overrideWithValue(playback),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: CoverflowOverlay(onDismiss: _noop, collection: requested),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('View album'), findsWidgets);

    // Merely showing either overlay must not reorder or replace the queue.
    expect(playback.queue.map((track) => track.id), ['q1', 'q2', 'q3']);
    expect(playback.currentIndex, 1);
    verifyNever(
      () => playback.replaceQueue(any(), startIndex: any(named: 'startIndex')),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });
}

void _noop() {}
