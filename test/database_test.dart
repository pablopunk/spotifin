import 'package:drift/drift.dart' show Migrator, Value;
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

  test('search filters in sqlite and limits results', () async {
    await database.upsertTracks([
      TracksCompanion.insert(
        id: 'match',
        name: 'Tiny Voices',
        artist: const Value('Box Car Racer'),
      ),
      TracksCompanion.insert(id: 'other', name: 'Different Song'),
    ]);

    final results = await database.searchTracks(['tiny', 'racer']).first;

    expect(results.map((track) => track.id), ['match']);
  });

  test('orders library tracks by date added with newest first', () async {
    await database.upsertTracks([
      TracksCompanion.insert(
        id: 'old',
        name: 'Old song',
        dateCreated: Value(DateTime(2025)),
      ),
      TracksCompanion.insert(id: 'unknown', name: 'Unknown date'),
      TracksCompanion.insert(
        id: 'new',
        name: 'New song',
        dateCreated: Value(DateTime(2026)),
      ),
    ]);

    final tracks = await database.watchTracksByDateAdded().first;

    expect(tracks.map((track) => track.id), ['new', 'old', 'unknown']);
  });

  test('version 4 migration accepts an existing tracks index', () async {
    await database.allTracks();

    await database.migration.onUpgrade(Migrator(database), 3, 4);

    expect(await database.allTracks(), isEmpty);
  });

  test('creation accepts existing tables and tracks index', () async {
    await database.allTracks();

    await database.migration.onCreate(Migrator(database));

    expect(await database.allTracks(), isEmpty);
  });

  test('persists Downtify imports per Jellyfin account', () async {
    final now = DateTime(2026);
    await database.putDowntifyImport(
      DowntifyImportsCompanion.insert(
        id: 'server:user:song',
        jellyfinServerId: 'server',
        jellyfinUserId: 'user',
        downtifyUrl: 'https://downtify.example.com',
        externalSongId: 'song',
        songJson: '{}',
        status: 'queued',
        createdAt: now,
        updatedAt: now,
      ),
    );

    expect(await database.getDowntifyImports('server', 'user'), hasLength(1));
    expect(await database.getDowntifyImports('server', 'other'), isEmpty);
  });

  test('version 5 migration creates Downtify imports', () async {
    await database.migration.onUpgrade(Migrator(database), 4, 5);

    expect(database.downtifyImports.actualTableName, 'downtify_imports');
  });
}
