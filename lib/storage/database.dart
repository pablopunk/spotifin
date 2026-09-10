import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

@TableIndex(name: 'tracks_name', columns: {#name})
class Tracks extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get album => text().withDefault(const Constant(''))();
  TextColumn get albumId => text().nullable()();
  TextColumn get artist =>
      text().withDefault(const Constant('Unknown artist'))();
  TextColumn get artistIds => text().withDefault(const Constant('[]'))();
  TextColumn get labels => text().withDefault(const Constant('[]'))();
  IntColumn get durationTicks => integer().withDefault(const Constant(0))();
  TextColumn get imageTag => text().nullable()();
  TextColumn get container => text().withDefault(const Constant('mp3'))();
  BoolColumn get favorite => boolean().withDefault(const Constant(false))();
  IntColumn get playCount => integer().withDefault(const Constant(0))();
  RealColumn get normalizationGain => real().nullable()();
  RealColumn get albumNormalizationGain => real().nullable()();
  DateTimeColumn get lastPlayed => dateTime().nullable()();
  DateTimeColumn get dateCreated => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Playlists extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get trackIds => text().withDefault(const Constant('[]'))();
  TextColumn get imageTag => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Downloads extends Table {
  TextColumn get trackId => text()();
  TextColumn get status => text()();
  TextColumn get localUri => text().nullable()();
  TextColumn get error => text().nullable()();
  IntColumn get receivedBytes => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {trackId};
}

class PendingWrites extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get targetId => text()();
  TextColumn get payload => text().withDefault(const Constant('{}'))();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [Tracks, Playlists, Downloads, PendingWrites])
class AppDatabase extends _$AppDatabase {
  AppDatabase()
    : super(
        driftDatabase(
          name: 'spotifin',
          web: DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.js'),
          ),
        ),
      );

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createTable(tracks);
      await migrator.createTable(playlists);
      await migrator.createTable(downloads);
      await migrator.createTable(pendingWrites);
      await customStatement(
        'CREATE INDEX IF NOT EXISTS tracks_name ON tracks (name)',
      );
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(tracks, tracks.normalizationGain);
        await migrator.addColumn(tracks, tracks.albumNormalizationGain);
      }
      if (from < 3) {
        await migrator.addColumn(tracks, tracks.container);
      }
      if (from < 4) {
        await customStatement(
          'CREATE INDEX IF NOT EXISTS tracks_name ON tracks (name)',
        );
      }
    },
  );

  Stream<List<Track>> watchTracks() =>
      (select(tracks)..orderBy([(row) => OrderingTerm.asc(row.name)])).watch();

  Future<List<Track>> allTracks() => select(tracks).get();

  Stream<List<Track>> searchTracks(List<String> words, {int limit = 30}) {
    final query = select(tracks)
      ..where((track) {
        Expression<bool>? predicate;
        for (final word in words) {
          final pattern = '%${_escapeLike(word)}%';
          final matches =
              track.name.like(pattern) |
              track.artist.like(pattern) |
              track.album.like(pattern);
          predicate = predicate == null ? matches : predicate & matches;
        }
        return predicate ?? const Constant(false);
      })
      ..orderBy([(track) => OrderingTerm.asc(track.name)])
      ..limit(limit);
    return query.watch();
  }

  String _escapeLike(String value) => value.replaceAll(RegExp(r'[%_]'), '');

  Future<void> upsertTracks(List<TracksCompanion> rows) =>
      batch((batch) => batch.insertAllOnConflictUpdate(tracks, rows));

  Future<void> replaceTracks(List<TracksCompanion> rows) =>
      transaction(() async {
        final ids = rows.map((row) => row.id.value).toList(growable: false);
        if (ids.isEmpty) {
          await delete(tracks).go();
          return;
        }
        await batch((batch) => batch.insertAllOnConflictUpdate(tracks, rows));
        await (delete(tracks)..where((row) => row.id.isNotIn(ids))).go();
      });

  Future<void> removeTracksExcept(List<String> ids) async {
    if (ids.isEmpty) {
      await delete(tracks).go();
      return;
    }
    await (delete(tracks)..where((track) => track.id.isNotIn(ids))).go();
  }

  Future<void> setFavorite(String id, bool value) =>
      (update(tracks)..where((row) => row.id.equals(id))).write(
        TracksCompanion(favorite: Value(value)),
      );

  Future<void> saveFavoriteEdit(String trackId, bool favorite) =>
      transaction(() async {
        await (update(tracks)..where((row) => row.id.equals(trackId))).write(
          TracksCompanion(favorite: Value(favorite)),
        );
        await (delete(pendingWrites)..where(
              (row) =>
                  row.kind.equals('favorite') & row.targetId.equals(trackId),
            ))
            .go();
        await into(pendingWrites).insert(
          PendingWritesCompanion.insert(
            id: 'favorite-$trackId-${DateTime.now().microsecondsSinceEpoch}',
            kind: 'favorite',
            targetId: trackId,
            payload: Value(jsonEncode({'favorite': favorite})),
            createdAt: DateTime.now(),
          ),
        );
      });

  Stream<List<Playlist>> watchPlaylists() => (select(
    playlists,
  )..orderBy([(row) => OrderingTerm.asc(row.name)])).watch();

  Future<void> replacePlaylists(List<PlaylistsCompanion> rows) =>
      transaction(() async {
        await delete(playlists).go();
        await batch((batch) => batch.insertAll(playlists, rows));
      });

  Future<void> savePlaylistAddition(String playlistId, String trackId) =>
      transaction(() async {
        final playlist = await (select(
          playlists,
        )..where((row) => row.id.equals(playlistId))).getSingle();
        final ids =
            (jsonDecode(playlist.trackIds) as List<dynamic>).cast<String>()
              ..add(trackId);
        await (update(playlists)..where((row) => row.id.equals(playlistId)))
            .write(PlaylistsCompanion(trackIds: Value(jsonEncode(ids))));
        await into(pendingWrites).insert(
          PendingWritesCompanion.insert(
            id: 'playlist-$playlistId-${DateTime.now().microsecondsSinceEpoch}',
            kind: 'playlistAdd',
            targetId: playlistId,
            payload: Value(jsonEncode({'trackId': trackId})),
            createdAt: DateTime.now(),
          ),
        );
      });

  Future<List<PendingWrite>> pendingOperations() => (select(
    pendingWrites,
  )..orderBy([(row) => OrderingTerm.asc(row.createdAt)])).get();

  Future<void> completePending(String id) =>
      (delete(pendingWrites)..where((row) => row.id.equals(id))).go();

  Future<void> incrementPendingAttempts(String id) => customUpdate(
    'UPDATE pending_writes SET attempts = attempts + 1 WHERE id = ?',
    variables: [Variable(id)],
    updates: {pendingWrites},
  );

  Stream<List<Download>> watchDownloads() => select(downloads).watch();

  Future<void> putDownload(DownloadsCompanion row) =>
      into(downloads).insertOnConflictUpdate(row);

  Future<void> removeDownload(String trackId) =>
      (delete(downloads)..where((row) => row.trackId.equals(trackId))).go();

  Future<void> clearAccountData() => transaction(() async {
    await delete(pendingWrites).go();
    await delete(downloads).go();
    await delete(playlists).go();
    await delete(tracks).go();
  });
}
