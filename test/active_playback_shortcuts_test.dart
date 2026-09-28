import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:spotifin/app/app.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/app/state/app_controller.dart';
import 'package:spotifin/services/cast/cast_controller.dart';
import 'package:spotifin/services/cast/cast_sender.dart';
import 'package:spotifin/services/jellyfin/session.dart';
import 'package:spotifin/services/playback/active_playback_state.dart';
import 'package:spotifin/services/playback/playback_service.dart';
import 'package:spotifin/services/playback/remote_session_service.dart';
import 'package:spotifin/services/updates/update_controller.dart';
import 'package:spotifin/storage/database.dart';

import 'support/fake_active_playback.dart';

class _MockPlayback extends Mock implements PlaybackService {}

class _MockCast extends Mock implements CastController {}

class _MockRemoteSessions extends Mock implements RemoteSessionService {}

class _ReadyAppController extends AppController {
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

  @override
  Future<void> initialize() async {}

  @override
  Future<void> refresh({bool silent = false, bool force = false}) async {}
}

class _IdleUpdateController extends UpdateController {
  @override
  UpdateState build() => const UpdateState();

  @override
  Future<void> checkOnStartup() async {}
}

Track _track(String id, String name) => Track(
  id: id,
  name: name,
  album: 'Album',
  albumId: 'album-$id',
  artist: 'Artist',
  artistItems: '[]',
  labels: '[]',
  durationTicks: 1800000000,
  favorite: false,
  playCount: 0,
  normalizationGain: null,
  albumNormalizationGain: null,
  container: 'mp3',
);

ActivePlaybackState _ownerState(Track track) => ActivePlaybackState(
  destination: PlaybackDestination.local,
  track: track,
  index: 0,
  entryId: 'entry-0',
  queue: [track],
  upcoming: [track],
  upcomingOffset: 0,
  history: const [],
  playing: true,
  position: Duration.zero,
  duration: const Duration(minutes: 3),
  volumeSlider: 1,
  shuffle: false,
  repeatMode: LoopMode.off,
  busy: false,
  recovering: false,
  capabilities: PlaybackCapability.values.toSet(),
);

void main() {
  setUpAll(() {
    registerFallbackValue(
      const JellyfinSession(
        serverUrl: 'https://jellyfin.example.com',
        serverId: 'server',
        deviceId: 'device',
        userId: 'user',
        userName: 'Pablo',
        accessToken: 'token',
      ),
    );
  });

  testWidgets('keyboard shortcuts route through the active owner', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final active = FakeActivePlayback();
    final playback = _MockPlayback();
    when(() => playback.addListener(any())).thenReturn(null);
    when(() => playback.removeListener(any())).thenReturn(null);
    when(() => playback.queue).thenReturn(const []);
    when(() => playback.upcomingQueue).thenReturn(const []);
    when(() => playback.currentTrack).thenReturn(null);
    when(() => playback.currentIndex).thenReturn(null);
    when(() => playback.history).thenReturn(const []);
    when(() => playback.playing).thenReturn(false);
    when(() => playback.shuffle).thenReturn(false);
    when(() => playback.loopMode).thenReturn(LoopMode.off);
    when(() => playback.volume).thenReturn(1);
    final cast = _MockCast();
    when(() => cast.addListener(any())).thenReturn(null);
    when(() => cast.removeListener(any())).thenReturn(null);
    when(() => cast.isSupported).thenReturn(false);
    when(() => cast.isCasting).thenReturn(false);
    when(() => cast.connectionState)
        .thenReturn(CastConnectionState.disconnected);
    when(() => cast.connectedDeviceName).thenReturn(null);
    final remote = _MockRemoteSessions();
    when(() => remote.addListener(any())).thenReturn(null);
    when(() => remote.removeListener(any())).thenReturn(null);
    when(() => remote.sessions).thenReturn([]);
    when(() => remote.configure(any())).thenAnswer((_) async {});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          activePlaybackProvider.overrideWithValue(active),
          appControllerProvider.overrideWith(_ReadyAppController.new),
          playbackProvider.overrideWithValue(playback),
          castControllerProvider.overrideWithValue(cast),
          remoteSessionProvider.overrideWithValue(remote),
          updateControllerProvider.overrideWith(_IdleUpdateController.new),
          packageInfoProvider.overrideWithValue(
            AsyncValue.data(
              PackageInfo(
                appName: 'Spotifin',
                packageName: 'com.spotifin',
                version: '0.0.0',
                buildNumber: '1',
              ),
            ),
          ),
        ],
        child: const SpotifinApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 1));

    active.emit(_ownerState(_track('a', 'Song A')));
    await tester.pump();

    // Focus a shell destination so hardware keys reach the app actions.
    final destinations = find.byType(NavigationDestination);
    expect(destinations, findsWidgets);
    await tester.tap(destinations.first);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(active.actions, contains('toggle'));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(active.actions, contains('next'));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(active.actions, contains('previous'));

    // Focused text fields keep keystrokes: the app shortcut must not
    // fire while a field consumes the key.
    active.actions.clear();
    final fields = find.byType(EditableText);
    if (fields.evaluate().isNotEmpty) {
      await tester.showKeyboard(fields.first);
      await tester.pump();
      final field = fields.first.evaluate().single.widget as EditableText;
      expect(field.focusNode.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(active.actions, isEmpty);
    }

    await tester.pump(const Duration(seconds: 2));
    // Flush the Play Library link timeout (no native channel in tests).
    await tester.pump(const Duration(seconds: 20));
    await tester.runAsync(database.close);
  });
}
