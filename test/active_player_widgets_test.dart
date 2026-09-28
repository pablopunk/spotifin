import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/app/state/app_controller.dart';
import 'package:spotifin/features/player/player_bar.dart';
import 'package:spotifin/services/cast/cast_controller.dart';
import 'package:spotifin/services/cast/cast_sender.dart';
import 'package:spotifin/services/jellyfin/session.dart';
import 'package:spotifin/services/lyrics/lyrics_service.dart';
import 'package:spotifin/services/lyrics/lyric_line.dart';
import 'package:spotifin/services/playback/active_playback_state.dart';
import 'package:spotifin/services/playback/remote_session_service.dart';
import 'package:spotifin/storage/database.dart';

import 'support/fake_active_playback.dart';

class _MockRemoteSessions extends Mock implements RemoteSessionService {}

class _MockCast extends Mock implements CastController {}

class _MockLyrics extends Mock implements LyricsService {}

class _AuthenticatedAppController extends AppController {
  @override
  AppState build() => const AppState(
    status: AppStatus.ready,
    session: JellyfinSession(
      serverUrl: 'https://jellyfin.example.com',
      serverId: 'server',
      deviceId: 'device',
      userId: 'user',
      userName: 'Pablo',
      accessToken: 'token',
    ),
  );
}

class _FakeSession extends Fake implements JellyfinSession {}

class _FakeTrack extends Fake implements Track {}

Track _track(String id, String name) => Track(
  id: id,
  name: name,
  album: 'Album',
  albumId: 'album-$id',
  artist: 'Artist $id',
  artistItems: '[]',
  labels: '[]',
  durationTicks: 1800000000,
  favorite: false,
  playCount: 0,
  normalizationGain: null,
  albumNormalizationGain: null,
  container: 'mp3',
);

ActivePlaybackState _localState(Track track) => ActivePlaybackState(
  destination: PlaybackDestination.local,
  track: track,
  index: 0,
  entryId: 'entry-local',
  queue: [track],
  upcoming: [track],
  upcomingOffset: 0,
  history: const [],
  playing: true,
  position: const Duration(seconds: 10),
  duration: const Duration(minutes: 3),
  volumeSlider: 1,
  shuffle: false,
  repeatMode: LoopMode.off,
  busy: false,
  recovering: false,
  capabilities: PlaybackCapability.values.toSet(),
);

ActivePlaybackState _castState({
  required Track track,
  bool playing = true,
  Duration position = const Duration(seconds: 30),
  bool recovering = false,
}) => ActivePlaybackState(
  destination: PlaybackDestination.cast,
  track: track,
  index: 0,
  entryId: 'entry-remote',
  queue: [track],
  upcoming: [track],
  upcomingOffset: 0,
  history: const [],
  playing: playing,
  position: position,
  duration: const Duration(minutes: 3),
  volumeSlider: 0.4,
  shuffle: false,
  repeatMode: LoopMode.off,
  busy: false,
  recovering: recovering,
  capabilities: recovering
      ? const {}
      : const {
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
    registerFallbackValue(_FakeSession());
    registerFallbackValue(const Duration(seconds: 1));
  });

  Future<void> pumpBar(
    WidgetTester tester,
    FakeActivePlayback active, {
    LyricsService? lyrics,
    Size size = const Size(390, 844),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final remote = _MockRemoteSessions();
    when(() => remote.addListener(any())).thenReturn(null);
    when(() => remote.removeListener(any())).thenReturn(null);
    when(() => remote.sessions).thenReturn([]);
    // The device picker controller is stubbed so no real sender, database,
    // or discovery work starts while the owner drives the UI.
    final cast = _MockCast();
    when(() => cast.addListener(any())).thenReturn(null);
    when(() => cast.removeListener(any())).thenReturn(null);
    when(() => cast.isSupported).thenReturn(false);
    when(() => cast.isCasting).thenReturn(false);
    when(() => cast.connectionState)
        .thenReturn(CastConnectionState.disconnected);
    when(() => cast.connectedDeviceName).thenReturn(null);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activePlaybackProvider.overrideWithValue(active),
          appControllerProvider.overrideWith(_AuthenticatedAppController.new),
          remoteSessionProvider.overrideWithValue(remote),
          castControllerProvider.overrideWithValue(cast),
          if (lyrics != null) lyricsProvider.overrideWithValue(lyrics),
        ],
        child: const MaterialApp(home: Scaffold(body: PlayerBar())),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the remote track while casting', (tester) async {
    final active = FakeActivePlayback();
    await pumpBar(tester, active);

    active.emit(_localState(_track('local', 'Local Song')));
    await tester.pump();
    expect(find.text('Local Song'), findsOneWidget);

    active.emit(_castState(track: _track('remote', 'Remote Song')));
    await tester.pump();
    expect(find.text('Remote Song'), findsOneWidget);
    expect(find.text('Casting to Living Room · Artist remote'), findsOneWidget);
    expect(find.text('Local Song'), findsNothing);
  });

  testWidgets('paused cast routes toggle to the owner', (tester) async {
    final active = FakeActivePlayback();
    await pumpBar(tester, active);
    active.emit(
      _castState(track: _track('remote', 'Remote Song'), playing: false),
    );
    await tester.pump();

    expect(find.text('Remote Song'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    expect(active.actions, ['toggle']);
  });

  testWidgets('local to cast to local updates', (tester) async {
    final active = FakeActivePlayback();
    await pumpBar(tester, active);

    active.emit(_localState(_track('a', 'Song A')));
    await tester.pump();
    expect(find.text('Song A'), findsOneWidget);

    active.emit(_castState(track: _track('b', 'Song B')));
    await tester.pump();
    expect(find.text('Song B'), findsOneWidget);

    active.emit(_localState(_track('a', 'Song A')));
    await tester.pump();
    expect(find.text('Song A'), findsOneWidget);
    expect(find.text('Song B'), findsNothing);
  });

  testWidgets('receiver loss retains the recovery display', (tester) async {
    final active = FakeActivePlayback();
    await pumpBar(tester, active);

    active.emit(
      _castState(track: _track('remote', 'Remote Song'), recovering: true),
    );
    await tester.pump();

    // The bar stays visible with the recovery track even though no local
    // track is selected.
    expect(find.text('Remote Song'), findsOneWidget);
  });

  testWidgets('remote lyric progress seeks through the owner', (tester) async {
    final lyrics = _MockLyrics();
    when(() => lyrics.find(any(), any())).thenAnswer(
      (_) async => const [
        LyricLine('hello', Duration(seconds: 10)),
        LyricLine('world', Duration(seconds: 60)),
      ],
    );
    final active = FakeActivePlayback();
    await pumpBar(tester, active, lyrics: lyrics, size: const Size(390, 1400));
    active.emit(_castState(track: _track('remote', 'Remote Song')));
    await tester.pump();

    // Open the now-playing sheet and switch to the Lyrics tab.
    await tester.tap(find.text('Remote Song'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Lyrics'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('hello'), findsOneWidget);
    expect(find.text('world'), findsOneWidget);

    await tester.tap(find.text('world'));
    await tester.pump();
    expect(active.actions, contains('seek'));
    expect(active.actionArguments['seek'], [const Duration(seconds: 60)]);
  });

  testWidgets('queue actions route through the owner while casting', (
    tester,
  ) async {
    final active = FakeActivePlayback();
    await pumpBar(tester, active);
    active.emit(_castState(track: _track('remote', 'Remote Song')));
    await tester.pump();

    await tester.tap(find.text('Remote Song'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));
    // Queue is the default details tab.
    expect(find.text('Remote Song'), findsWidgets);

    await tester.tap(find.byTooltip('Next').last);
    await tester.pump();
    expect(active.actions, contains('next'));
  });
}
