import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/features/player/player_side_panel.dart';
import 'package:spotifin/services/playback/playback_service.dart';
import 'package:spotifin/services/playback/remote_session_service.dart';
import 'package:spotifin/storage/database.dart';

class _Playback extends Mock implements PlaybackService {}

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

void main() {
  testWidgets('desktop queue hides played tracks and maps queue actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final playback = _Playback();
    final remote = _RemoteSessions();
    final played = _track('Played');
    final current = _track('Current');
    final next = _track('Next');
    when(() => playback.addListener(any())).thenReturn(null);
    when(() => playback.removeListener(any())).thenReturn(null);
    when(() => remote.addListener(any())).thenReturn(null);
    when(() => remote.removeListener(any())).thenReturn(null);
    when(() => remote.sessions).thenReturn([]);
    when(() => playback.currentTrack).thenReturn(current);
    when(() => playback.currentIndex).thenReturn(1);
    when(() => playback.queue).thenReturn([played, current, next]);
    when(() => playback.upcomingQueue).thenReturn([current, next]);
    when(() => playback.playUpcomingIndex(any())).thenAnswer((_) async {});
    when(() => playback.removeUpcomingAt(any())).thenAnswer((_) async {});

    final container = ProviderContainer(
      overrides: [
        playbackProvider.overrideWithValue(playback),
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
    verify(() => playback.playUpcomingIndex(1)).called(1);
    await tester.tap(find.byTooltip('Remove from queue').last);
    verify(() => playback.removeUpcomingAt(1)).called(1);
  });
}
