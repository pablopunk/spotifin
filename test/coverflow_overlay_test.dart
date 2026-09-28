import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/app/theme.dart';
import 'package:spotifin/features/common/design_system.dart';
import 'package:spotifin/features/coverflow/coverflow_controller.dart';
import 'package:spotifin/features/coverflow/coverflow_model.dart';
import 'package:spotifin/features/coverflow/coverflow_overlay.dart';
import 'package:spotifin/features/coverflow/coverflow_stage.dart';
import 'package:spotifin/services/playback/active_playback_state.dart';
import 'package:spotifin/storage/database.dart';

import 'support/fake_active_playback.dart';

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

ActivePlaybackState _ownerState({
  List<Track> queue = const [],
  int? index,
  Track? track,
  bool playing = false,
}) => ActivePlaybackState(
  destination: PlaybackDestination.local,
  track: track,
  index: index,
  entryId: track == null ? null : 'entry-0',
  queue: queue,
  upcoming: index == null ? queue : queue.sublist(index),
  upcomingOffset: index ?? 0,
  history: const [],
  playing: playing,
  position: Duration.zero,
  duration: Duration.zero,
  volumeSlider: 1,
  shuffle: false,
  repeatMode: LoopMode.off,
  busy: false,
  recovering: false,
  capabilities: PlaybackCapability.values.toSet(),
);

ActivePlaybackState _castOwnerState({required List<Track> queue}) =>
    ActivePlaybackState(
      destination: PlaybackDestination.cast,
      track: queue.first,
      index: 0,
      entryId: 'entry-remote',
      queue: queue,
      upcoming: queue,
      upcomingOffset: 0,
      history: const [],
      playing: true,
      position: Duration.zero,
      duration: Duration.zero,
      volumeSlider: 0.4,
      shuffle: false,
      repeatMode: LoopMode.off,
      busy: false,
      recovering: false,
      capabilities: const {
        PlaybackCapability.transport,
        PlaybackCapability.seek,
        PlaybackCapability.volume,
        PlaybackCapability.selection,
        PlaybackCapability.queueEditing,
        PlaybackCapability.shuffle,
      },
      connectedDeviceName: 'Living Room',
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
    final active = FakeActivePlayback();
    final queue = [_track('1', 'First'), _track('2', 'Second')];
    active.emit(_ownerState(queue: queue, index: 0, track: queue.first));

    var dismissed = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          activePlaybackProvider.overrideWithValue(active),
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
    expect(find.textContaining('First'), findsWidgets);
    expect(find.byType(SpotifinPlayButton), findsOneWidget);
    expect(find.byTooltip('Previous'), findsNothing);
    expect(find.byTooltip('Next'), findsNothing);
    expect(find.byTooltip('Dismiss'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Cover for First'));
    await tester.pump();
    expect(active.actions, ['toggle']);

    await tester.fling(
      find.byType(CoverflowStage),
      const Offset(-400, 0),
      1000,
    );
    await tester.pumpAndSettle();
    // Browsing alone sends no playback action.
    expect(active.actions.where((action) => action != 'toggle'), isEmpty);
    expect(find.textContaining('Second'), findsWidgets);

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
    final active = FakeActivePlayback()..emit(_ownerState());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          activePlaybackProvider.overrideWithValue(active),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(body: CoverflowOverlay(onDismiss: () {})),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Lonely song'), findsWidgets);
    expect(find.byTooltip('Previous'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });

  testWidgets('overlay uses the active collection instead of the queue', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final active = FakeActivePlayback();
    final queued = _track('queue', 'Queued song');
    final albumTrack = _track('album-track', 'Album song');
    active.emit(_ownerState(queue: [queued], index: 0, track: queued));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          activePlaybackProvider.overrideWithValue(active),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: CoverflowOverlay(
              onDismiss: () {},
              collection: MobileCoverflowCollection(
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
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Selected album'), findsWidgets);
    expect(find.textContaining('Queued song'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('art:album:selected')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Album song'), findsOneWidget);
    await tester.tap(find.textContaining('Album song'));
    expect(active.actions, ['playTrack']);
    expect(active.actionArguments['playTrack'], [
      albumTrack,
      [albumTrack],
    ]);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });

  testWidgets('coverflow selection stays on Cast while casting', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final active = FakeActivePlayback();
    final remote = _track('remote', 'Remote song');
    final remoteNext = _track('remote-next', 'Remote next');
    active.emit(_castOwnerState(queue: [remote, remoteNext]));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          activePlaybackProvider.overrideWithValue(active),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(body: CoverflowOverlay(onDismiss: () {})),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Remote song'), findsWidgets);
    await tester.tap(find.bySemanticsLabel('Cover for Remote song'));
    await tester.pump();
    // Tapping the current cover toggles instead of starting local audio.
    expect(active.actions, ['toggle']);
  });
}
