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

  test('matches only exact play library action links', () {
    expect(isPlayLibraryLink('spotifin://play-library'), isTrue);
    expect(isPlayLibraryLink('spotifin://play-library-shuffle'), isTrue);
    expect(isPlayLibraryLink('spotifin://play-library-in-order'), isTrue);
    expect(isPlayLibraryLink(null), isFalse);
    expect(isPlayLibraryLink(''), isFalse);
    expect(isPlayLibraryLink('spotifin://play-librar'), isFalse);
    expect(isPlayLibraryLink('spotifin://play-library/extra'), isFalse);
    expect(isPlayLibraryLink('spotifin://play-library?shuffle=true'), isFalse);
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

  testWidgets('library shortcuts choose shuffle or ordered playback', (
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

    await handlePlayLibraryLink(
      captured!,
      'spotifin://play-library-shuffle?x=1',
    );
    // Exact-link matching rejects decorated links: nothing runs.
    expect(active.actions, isEmpty);

    await handlePlayLibraryLink(captured!, playLibraryShuffleLink);
    expect(active.actions, ['replaceQueue']);
    expect(active.actionArguments['replaceQueue']![1], isNull);
    expect(active.actionArguments['replaceQueue']![2], isTrue);

    // Keep the original URL working as an alias for the shuffled action.
    await handlePlayLibraryLink(captured!, playLibraryLink);
    expect(active.actions, ['replaceQueue', 'replaceQueue']);
    expect(active.actionArguments['replaceQueue']![1], isNull);
    expect(active.actionArguments['replaceQueue']![2], isTrue);

    await handlePlayLibraryLink(captured!, playLibraryInOrderLink);
    expect(active.actions, ['replaceQueue', 'replaceQueue', 'replaceQueue']);
    expect(active.actionArguments['replaceQueue']![1], 0);
    expect(active.actionArguments['replaceQueue']![2], isFalse);

    // Cold-start configuration remains local; both queue actions route
    // through the active playback owner.
    verify(
      () => playback.configure(
        any(),
        smallStreaming: any(named: 'smallStreaming'),
        normalization: any(named: 'normalization'),
      ),
    ).called(3);
  });
}
