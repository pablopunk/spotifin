import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/services/jellyfin/session.dart';
import 'package:spotifin/storage/database.dart';

import 'support/fake_active_playback.dart';

const _session = JellyfinSession(
  serverUrl: 'https://music.example.com',
  serverId: 'server',
  deviceId: 'device',
  userId: 'user',
  userName: 'Pablo',
  accessToken: 'token',
);

const _otherSession = JellyfinSession(
  serverUrl: 'https://music.example.com',
  serverId: 'server',
  deviceId: 'device',
  userId: 'other',
  userName: 'Other',
  accessToken: 'token',
);

Track _track(String id) => Track(
  id: id,
  name: 'Song $id',
  album: 'Album',
  artist: 'Artist',
  artistItems: '[]',
  labels: '[]',
  durationTicks: 0,
  container: 'mp3',
  favorite: false,
  playCount: 0,
);

Future<void> _eventually(bool Function() check) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!check()) {
    if (DateTime.now().isAfter(deadline)) break;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(check(), isTrue);
}

void main() {
  ProviderContainer makeContainer(AppDatabase database) => ProviderContainer(
    overrides: [databaseProvider.overrideWithValue(database)],
  );

  test('initial state is signed out and empty', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final container = makeContainer(database);
    addTearDown(container.dispose);

    final state = container.read(carControllerProvider);
    expect(state.signedIn, isFalse);
    expect(state.tracks, isEmpty);
    expect(state.playlists, isEmpty);
  });

  test(
    'committed catalog edits update car state without manual refresh',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final container = makeContainer(database);
      addTearDown(container.dispose);
      final scope = container.read(accountScopeProvider);
      scope.activate(_session);

      await _eventually(() => container.read(carControllerProvider).signedIn);

      await database.upsertTracks([
        TracksCompanion.insert(id: 'a', name: 'Alpha'),
      ]);
      await _eventually(
        () => container
            .read(carControllerProvider)
            .tracks
            .map((track) => track.id)
            .contains('a'),
      );

      // Local favorites flow through the same committed stream.
      await database.setFavorite('a', true);
      await _eventually(
        () => container
            .read(carControllerProvider)
            .tracks
            .singleWhere((track) => track.id == 'a')
            .favorite,
      );

      // Playlist addition, rename, and delete are observed too.
      await database
          .into(database.playlists)
          .insert(
            PlaylistsCompanion.insert(
              id: 'p',
              name: 'Mix',
              trackIds: const Value('["a"]'),
            ),
          );
      await _eventually(
        () => container
            .read(carControllerProvider)
            .playlists
            .map((playlist) => playlist.id)
            .contains('p'),
      );
      await database.removePlaylist('p');
      await _eventually(
        () => container.read(carControllerProvider).playlists.isEmpty,
      );

      // Track deletion is observed without a manual refresh call.
      await database.removeTrack('a');
      await _eventually(
        () => container.read(carControllerProvider).tracks.isEmpty,
      );
    },
  );

  test('invalidation clears state before held old events publish', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final container = makeContainer(database);
    addTearDown(container.dispose);
    final scope = container.read(accountScopeProvider);
    scope.activate(_session);
    await _eventually(() => container.read(carControllerProvider).signedIn);
    await database.upsertTracks([
      TracksCompanion.insert(id: 'a', name: 'Alpha'),
    ]);
    await _eventually(
      () => container.read(carControllerProvider).tracks.isNotEmpty,
    );

    scope.invalidate();
    // Synchronous invalidation publishes the empty state immediately.
    expect(container.read(carControllerProvider).signedIn, isFalse);
    expect(container.read(carControllerProvider).tracks, isEmpty);

    // Late rows from the old account never return.
    await database.upsertTracks([
      TracksCompanion.insert(id: 'stale', name: 'Stale'),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(container.read(carControllerProvider).signedIn, isFalse);
    expect(container.read(carControllerProvider).tracks, isEmpty);
  });

  test('new activation drops the previous catalog', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final container = makeContainer(database);
    addTearDown(container.dispose);
    final scope = container.read(accountScopeProvider);
    scope.activate(_session);
    await database.upsertTracks([
      TracksCompanion.insert(id: 'a', name: 'Alpha'),
    ]);
    await _eventually(
      () => container.read(carControllerProvider).tracks.isNotEmpty,
    );

    scope.activate(_otherSession);
    // The previous catalog drops synchronously; old subscriptions are
    // cancelled before the new account subscribes fresh.
    expect(container.read(carControllerProvider).signedIn, isTrue);
    expect(container.read(carControllerProvider).tracks, isEmpty);

    await database.upsertTracks([
      TracksCompanion.insert(id: 'b', name: 'Bravo'),
    ]);
    await _eventually(
      () => container
          .read(carControllerProvider)
          .tracks
          .map((track) => track.id)
          .contains('b'),
    );
  });

  test('playTrack delegates to the active owner', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final active = FakeActivePlayback();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        activePlaybackProvider.overrideWithValue(active),
      ],
    );
    addTearDown(container.dispose);
    final track = _track('a');
    await container.read(carControllerProvider.notifier).playTrack(track, [
      track,
    ]);
    expect(active.actions, ['playTrack']);
    expect(active.actionArguments['playTrack'], [
      track,
      [track],
    ]);
  });

  test('playTracks delegates queue replacement to the active owner', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final active = FakeActivePlayback();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        activePlaybackProvider.overrideWithValue(active),
      ],
    );
    addTearDown(container.dispose);
    final track = _track('a');
    await container
        .read(carControllerProvider.notifier)
        .playTracks([track], startIndex: 0, shuffle: true);
    expect(active.actions, ['replaceQueue']);
  });
}
