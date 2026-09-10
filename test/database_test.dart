import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/storage/database.dart';

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => database.close());

  test('favorite edits are local and coalesced', () async {
    await database.upsertTracks([
      TracksCompanion.insert(id: 'track', name: 'Track'),
    ]);

    await database.saveFavoriteEdit('track', true);
    await database.saveFavoriteEdit('track', false);

    final track = await (database.select(
      database.tracks,
    )..where((row) => row.id.equals('track'))).getSingle();
    final pending = await database.pendingOperations();
    expect(track.favorite, isFalse);
    expect(pending, hasLength(1));
    expect(pending.single.payload, '{"favorite":false}');
  });

  test('playlist additions keep duplicate entries in order', () async {
    await database.replacePlaylists([
      PlaylistsCompanion.insert(id: 'playlist', name: 'Playlist'),
    ]);

    await database.savePlaylistAddition('playlist', 'song');
    await database.savePlaylistAddition('playlist', 'song');

    final playlist = await database.select(database.playlists).getSingle();
    expect(playlist.trackIds, '["song","song"]');
    expect(await database.pendingOperations(), hasLength(2));
  });
}
