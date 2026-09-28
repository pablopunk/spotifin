import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:spotifin/app/providers.dart';
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

void main() {
  testWidgets('desktop queue hides played tracks and maps queue actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
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
    container.read(playerPanelProvider.notifier).togglePlayer();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: PlayerSidePanel())),
      ),
    );
    await tester.pump();

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
}
