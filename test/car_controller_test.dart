import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/services/playback/playback_service.dart';
import 'package:spotifin/storage/database.dart';

class _MockPlayback extends Mock implements PlaybackService {}

class _FakeTrack extends Fake implements Track {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeTrack());
    registerFallbackValue(<Track>[]);
  });

  Track makeTrack(String id, {String name = 'Song'}) => Track(
    id: id,
    name: name,
    album: 'Album',
    artist: 'Artist',
    artistItems: '[]',
    labels: '[]',
    durationTicks: 0,
    container: 'mp3',
    favorite: false,
    playCount: 0,
  );

  ProviderContainer makeContainer({
    AppDatabase? database,
    PlaybackService? playback,
  }) => ProviderContainer(
    overrides: [
      if (database != null) databaseProvider.overrideWithValue(database),
      if (playback != null) playbackProvider.overrideWithValue(playback),
    ],
  );

  test('initial state is signed out and empty', () {
    final container = makeContainer();
    addTearDown(container.dispose);
    final state = container.read(carControllerProvider);
    expect(state.signedIn, isFalse);
    expect(state.tracks, isEmpty);
    expect(state.playlists, isEmpty);
    expect(state.isEmpty, isTrue);
  });

  test('setSignedIn toggles without clearing catalog', () {
    final container = makeContainer();
    addTearDown(container.dispose);
    final controller = container.read(carControllerProvider.notifier);
    controller.refreshCatalog(tracks: [makeTrack('a')]);
    controller.setSignedIn(true);
    expect(container.read(carControllerProvider).signedIn, isTrue);
    expect(container.read(carControllerProvider).tracks, hasLength(1));
    controller.setSignedIn(false);
    expect(container.read(carControllerProvider).signedIn, isFalse);
    expect(container.read(carControllerProvider).tracks, hasLength(1));
  });

  test('refreshCatalog replaces snapshot', () {
    final container = makeContainer();
    addTearDown(container.dispose);
    final controller = container.read(carControllerProvider.notifier);
    controller.refreshCatalog(tracks: [makeTrack('a')]);
    controller.refreshCatalog(tracks: [makeTrack('b'), makeTrack('c')]);
    expect(container.read(carControllerProvider).tracks.map((t) => t.id), [
      'b',
      'c',
    ]);
  });

  test('refreshNow reads tracks and playlists from the database', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.upsertTracks([
      TracksCompanion.insert(id: 'a', name: 'Alpha'),
      TracksCompanion.insert(id: 'b', name: 'Bravo'),
    ]);
    await database.replacePlaylists([
      PlaylistsCompanion.insert(
        id: 'p',
        name: 'Mix',
        trackIds: const Value('["a","b"]'),
      ),
    ]);
    final container = makeContainer(database: database);
    addTearDown(container.dispose);
    await container.read(carControllerProvider.notifier).refreshNow();
    final state = container.read(carControllerProvider);
    expect(state.tracks.map((t) => t.id), containsAll(['a', 'b']));
    expect(state.playlists.map((p) => p.id), ['p']);
  });

  test('playTrack delegates to playback', () async {
    final playback = _MockPlayback();
    when(() => playback.playTrack(any(), any())).thenAnswer((_) async {});
    final container = makeContainer(playback: playback);
    addTearDown(container.dispose);
    final track = makeTrack('a');
    await container.read(carControllerProvider.notifier).playTrack(track, [
      track,
    ]);
    verify(() => playback.playTrack(track, [track])).called(1);
  });
}
