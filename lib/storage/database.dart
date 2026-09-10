import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

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
  BoolColumn get favorite => boolean().withDefault(const Constant(false))();
  IntColumn get playCount => integer().withDefault(const Constant(0))();
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
  AppDatabase() : super(driftDatabase(name: 'spotifin'));

  @override
  int get schemaVersion => 1;

  Stream<List<Track>> watchTracks() =>
      (select(tracks)..orderBy([(row) => OrderingTerm.asc(row.name)])).watch();

  Future<List<Track>> allTracks() => select(tracks).get();

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

  Future<void> setFavorite(String id, bool value) =>
      (update(tracks)..where((row) => row.id.equals(id))).write(
        TracksCompanion(favorite: Value(value)),
      );

  Stream<List<Playlist>> watchPlaylists() => (select(
    playlists,
  )..orderBy([(row) => OrderingTerm.asc(row.name)])).watch();

  Future<void> replacePlaylists(List<PlaylistsCompanion> rows) =>
      transaction(() async {
        await delete(playlists).go();
        await batch((batch) => batch.insertAll(playlists, rows));
      });

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
