import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/app/state/player_panel_controller.dart';
import 'package:spotifin/features/player/player_side_panel.dart';
import 'package:spotifin/services/playback/active_playback_state.dart';
import 'package:spotifin/services/playback/remote_session_service.dart';
import 'package:spotifin/storage/database.dart';

import 'support/fake_active_playback.dart';

class _RemoteSessions extends Mock implements RemoteSessionService {}

Track _track(String id) => Track(
  id: id,
  name: id,
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

ActivePlaybackState _queueState() {
  final played = _track('Played');
  final current = _track('Current');
  final next = _track('Next');
  return ActivePlaybackState(
    destination: PlaybackDestination.local,
    track: current,
    index: 1,
    entryId: 'entry-1',
    queue: [played, current, next],
    upcoming: [current, next],
    upcomingOffset: 1,
    history: const [],
    playing: false,
    position: Duration.zero,
    duration: Duration.zero,
    volumeSlider: 1,
    shuffle: false,
    repeatMode: LoopMode.off,
    busy: false,
    recovering: false,
    capabilities: PlaybackCapability.values.toSet(),
  );
}

Future<(FakeActivePlayback, ProviderContainer)> _pumpPanel(
  WidgetTester tester, {
  required Size size,
  bool showPlayer = false,
  bool sideBySide = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final active = FakeActivePlayback()..emit(_queueState());
  final remote = _RemoteSessions();
  when(() => remote.addListener(any())).thenReturn(null);
  when(() => remote.removeListener(any())).thenReturn(null);
  when(() => remote.sessions).thenReturn([]);

  final container = ProviderContainer(
    overrides: [
      activePlaybackProvider.overrideWithValue(active),
      remoteSessionProvider.overrideWithValue(remote),
    ],
  );
  addTearDown(container.dispose);
  if (!showPlayer) container.read(playerPanelProvider.notifier).togglePlayer();

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(body: PlayerSidePanel(sideBySide: sideBySide)),
      ),
    ),
  );
  await tester.pump();
  return (active, container);
}

void main() {
  testWidgets('desktop queue hides played tracks and maps queue actions', (
    tester,
  ) async {
    final (active, _) = await _pumpPanel(tester, size: const Size(900, 700));

    expect(find.text('Played'), findsNothing);
    expect(find.text('Current'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);

    await tester.tap(find.text('Next'));
    expect(active.actions, contains('playUpcomingIndex'));
    expect(active.actionArguments['playUpcomingIndex'], [1]);
    await tester.tap(find.byTooltip('Remove from queue').last);
    expect(active.actions, contains('removeUpcomingAt'));
    expect(active.actionArguments['removeUpcomingAt'], [1]);
  });

  testWidgets('now playing panel scrolls instead of overflowing when short', (
    tester,
  ) async {
    await _pumpPanel(tester, size: const Size(669, 300), showPlayer: true);

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsWidgets);
  });

  testWidgets('side by side panels sit in one row and cap at two', (
    tester,
  ) async {
    final (_, container) = await _pumpPanel(
      tester,
      size: const Size(669, 455),
      showPlayer: true,
      sideBySide: true,
    );

    container.read(playerPanelProvider.notifier).toggleHistory();
    await tester.pump();
    await tester.pump();

    final open = container.read(playerPanelProvider).openPanels;
    expect(open, hasLength(2));
    expect(open, contains(PlayerPanel.history));
    final queue = tester.getTopLeft(find.text('Queue'));
    final history = tester.getTopLeft(find.text('History'));
    expect(queue.dy, history.dy);
    expect(queue.dx, lessThan(history.dx));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
