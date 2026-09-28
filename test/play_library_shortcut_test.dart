import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/app/state/app_controller.dart';
import 'package:spotifin/services/jellyfin/session.dart';
import 'package:spotifin/services/playback/playback_service.dart';
import 'package:spotifin/services/shortcuts/play_library_handler.dart';
import 'package:spotifin/storage/database.dart';

import 'support/fake_active_playback.dart';

class _MockPlayback extends Mock implements PlaybackService {}

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
}

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

  test('matches only the exact play library link', () {
    expect(isPlayLibraryLink('spotifin://play-library'), isTrue);
    expect(isPlayLibraryLink(null), isFalse);
    expect(isPlayLibraryLink(''), isFalse);
    expect(isPlayLibraryLink('spotifin://play-librar'), isFalse);
    expect(isPlayLibraryLink('spotifin://play-library/extra'), isFalse);
    expect(isPlayLibraryLink('SPOTIFIN://play-library'), isFalse);
    expect(isPlayLibraryLink('https://play-library'), isFalse);
  });

  test('dedupe drops an immediate repeat but accepts a later run', () {
    final dedupe = PlayLibraryDedupe();
    final first = DateTime(2026, 9, 19, 12, 0, 0);
    expect(dedupe.shouldHandle('spotifin://play-library', first), isTrue);
    expect(
      dedupe.shouldHandle(
        'spotifin://play-library',
        first.add(const Duration(seconds: 1)),
      ),
      isFalse,
    );
    expect(
      dedupe.shouldHandle(
        'spotifin://play-library',
        first.add(const Duration(seconds: 4)),
      ),
      isTrue,
    );
  });

  test('dedupe rejects non library links', () {
    final dedupe = PlayLibraryDedupe();
    expect(dedupe.shouldHandle('spotifin://other', DateTime.now()), isFalse);
    expect(dedupe.shouldHandle(null, DateTime.now()), isFalse);
  });

  testWidgets('play library configures locally then replaces via the owner', (
    tester,
  ) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.upsertTracks([
      TracksCompanion.insert(id: 'a', name: 'A'),
      TracksCompanion.insert(id: 'b', name: 'B'),
    ]);
    final playback = _MockPlayback();
    when(
      () => playback.configure(
        any(),
        smallStreaming: any(named: 'smallStreaming'),
        normalization: any(named: 'normalization'),
      ),
    ).thenAnswer((_) async {});
    final active = FakeActivePlayback();
    WidgetRef? captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          appControllerProvider.overrideWith(_ReadyAppController.new),
          playbackProvider.overrideWithValue(playback),
          activePlaybackProvider.overrideWithValue(active),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            captured = ref;
            return const SizedBox();
          },
        ),
      ),
    );

    await handlePlayLibraryLink(captured!, 'spotifin://play-library?x=1');
    // Exact-link matching rejects decorated links: nothing runs.
    expect(active.actions, isEmpty);

    await handlePlayLibraryLink(captured!, 'spotifin://play-library');
    // Local configuration for cold start runs on local playback, while the
    // final queue replacement routes through the active owner.
    verify(
      () => playback.configure(
        any(),
        smallStreaming: any(named: 'smallStreaming'),
        normalization: any(named: 'normalization'),
      ),
    ).called(1);
    expect(active.actions, ['replaceQueue']);
  });
}
