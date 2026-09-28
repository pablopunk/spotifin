import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';

import '../services/search/search_text.dart';

part 'database.g.dart';

@TableIndex(name: 'tracks_name', columns: {#name})
class Tracks extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get album => text().withDefault(const Constant(''))();
  TextColumn get albumId => text().nullable()();
  TextColumn get artist =>
      text().withDefault(const Constant('Unknown artist'))();
  TextColumn get artistItems => text().withDefault(const Constant('[]'))();
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
  DateTimeColumn get premiereDate => dateTime().nullable()();

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

class DowntifyImports extends Table {
  TextColumn get id => text()();
  TextColumn get jellyfinServerId => text()();
  TextColumn get jellyfinUserId => text()();
  TextColumn get downtifyUrl => text()();
  TextColumn get externalSongId => text()();
  TextColumn get jobId => text().nullable()();
  TextColumn get songJson => text()();
  TextColumn get status => text()();
  RealColumn get progress => real().withDefault(const Constant(0))();
  TextColumn get message => text().withDefault(const Constant(''))();
  TextColumn get filename => text().nullable()();
  TextColumn get matchedTrackId => text().nullable()();
  BoolColumn get messageShown => boolean().withDefault(const Constant(false))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AlbumDates extends Table {
  TextColumn get albumId => text()();
  DateTimeColumn get premiereDate => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {albumId};
}

@DriftDatabase(
  tables: [
    Tracks,
    Playlists,
    Downloads,
    PendingWrites,
    DowntifyImports,
    AlbumDates,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase()
    : super(
        driftDatabase(
          name: kDebugMode ? 'spotifin-dev' : 'spotifin',
          web: DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.js'),
          ),
        ),
      );

  AppDatabase.forTesting(super.executor);

  /// Random per-instance prefix plus a monotonic counter for pending-write
  /// ids. Clock timestamps alone can repeat, so ids minted from time only
  /// would collide and lose operations; this pair stays distinct for every
  /// newly saved operation while already-stored ids are preserved.
  final String _pendingIdPrefix = math.Random()
      .nextInt(1 << 32)
      .toRadixString(16);
  int _pendingIdCounter = 0;

  /// Mints a distinct id for a newly saved pending operation.
  String newPendingWriteId(String kind, String targetId) =>
      '$kind-$targetId-$_pendingIdPrefix-${_pendingIdCounter++}';

  @override
  int get schemaVersion => 10;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createTable(tracks);
      await migrator.createTable(playlists);
      await migrator.createTable(downloads);
      await migrator.createTable(pendingWrites);
      await migrator.createTable(downtifyImports);
      await migrator.createTable(albumDates);
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
      if (from < 5) await migrator.createTable(downtifyImports);
      if (from < 7) {
        await customStatement('DROP TABLE IF EXISTS album_release_kinds');
        final columns = await customSelect('PRAGMA table_info(tracks)').get();
        final missing = !columns.any(
          (row) => row.read<String>('name') == 'premiere_date',
        );
        if (missing) await migrator.addColumn(tracks, tracks.premiereDate);
      }
      if (from < 8) await migrator.createTable(albumDates);
      if (from < 9) {
        final columns = await customSelect('PRAGMA table_info(tracks)').get();
        final legacy = columns.any(
          (row) => row.read<String>('name') == 'artist_ids',
        );
        if (legacy) {
          await customStatement(
            'ALTER TABLE tracks RENAME COLUMN artist_ids TO artist_items',
          );
        }
      }
      if (from >= 5 && from < 10) {
        final downtifyColumns = await customSelect(
          'PRAGMA table_info(downtify_imports)',
        ).get();
        final retryCountMissing = !downtifyColumns.any(
          (row) => row.read<String>('name') == 'retry_count',
        );
        if (retryCountMissing) {
          await migrator.addColumn(downtifyImports, downtifyImports.retryCount);
        }
      }
    },
  );

  Stream<List<Track>> watchTracks() =>
      (select(tracks)..orderBy([(row) => OrderingTerm.asc(row.name)])).watch();

  Stream<List<Track>> watchTracksByDateAdded() =>
      (select(tracks)..orderBy([
            (row) => OrderingTerm.desc(row.dateCreated),
            (row) => OrderingTerm.asc(row.name),
            (row) => OrderingTerm.asc(row.id),
          ]))
          .watch();

  /// Cached Jellyfin Recently Played list.
  ///
  /// Mirrors the server semantics of `fetchRecentlyPlayed` (`Filters=IsPlayed`
  /// ordered by `DatePlayed` descending): only tracks with a non-null
  /// `lastPlayed` (populated from Jellyfin `UserData.LastPlayedDate` during
  /// sync), most-recent-first. The local database is a cache of that server
  /// truth, so this stream stays available offline and updates on every
  /// library sync. Plays made since the last sync are *not* here yet; the UI
  /// merges a transient in-memory session overlay on top (see
  /// `mergeRecentlyPlayed`) instead of maintaining a second persisted
  /// history.
  Stream<List<Track>> watchRecentlyPlayed({int limit = 100}) =>
      (select(tracks)
            ..where((row) => row.lastPlayed.isNotNull())
            ..orderBy([
              (row) => OrderingTerm.desc(row.lastPlayed),
              (row) => OrderingTerm.asc(row.name),
              (row) => OrderingTerm.asc(row.id),
            ])
            ..limit(limit))
          .watch();

  Future<List<Track>> recentlyPlayed({int limit = 100}) =>
      (select(tracks)
            ..where((row) => row.lastPlayed.isNotNull())
            ..orderBy([
              (row) => OrderingTerm.desc(row.lastPlayed),
              (row) => OrderingTerm.asc(row.name),
              (row) => OrderingTerm.asc(row.id),
            ])
            ..limit(limit))
          .get();

  Future<List<Track>> allTracks() => select(tracks).get();

  Future<List<Track>> allTracksByDateAdded() =>
      (select(tracks)..orderBy([
            (row) => OrderingTerm.desc(row.dateCreated),
            (row) => OrderingTerm.asc(row.name),
            (row) => OrderingTerm.asc(row.id),
          ]))
          .get();

  /// Accent- and case-insensitive substring search over name/artist/album.
  ///
  /// Stays blazing fast: a single SQLite scan whose `LIKE '%token%'`
  /// predicates run against one accent-folded `name || artist || album`
  /// expression (nested `REPLACE`s, no extensions, works on native and web).
  /// Tokens are normalized with [normalizeSearchToken], so they only ever
  /// contain `a-z0-9` and are inherently `LIKE`-safe.
  Stream<List<Track>> searchTracks(List<String> words, {int limit = 30}) {
    final tokens = words
        .map(normalizeSearchToken)
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    final query = select(tracks)
      ..where((track) {
        if (tokens.isEmpty) return const Constant(false);
        final haystack = _foldedSearchHaystack(track);
        Expression<bool>? predicate;
        for (final token in tokens) {
          final matches = haystack.like('%$token%');
          predicate = predicate == null ? matches : predicate & matches;
        }
        return predicate!;
      })
      ..orderBy([(track) => OrderingTerm.asc(track.name)])
      ..limit(limit);
    return query.watch();
  }

  /// `LOWER(name || ' ' || artist || ' ' || album)` with diacritics folded
  /// to ASCII and punctuation stripped via nested `REPLACE` calls (see
  /// [sqlFoldReplacements] and [sqlStripReplacements]).
  ///
  /// One concatenated expression instead of three per-column folds keeps the
  /// per-row cost of the scan to a single fold chain per query word.
  Expression<String> _foldedSearchHaystack($TracksTable track) {
    Expression<String> haystack =
        track.name +
        const Constant(' ') +
        track.artist +
        const Constant(' ') +
        track.album;
    haystack = haystack.lower();
    for (final replacement in sqlFoldReplacements) {
      haystack = FunctionCallExpression<String>('REPLACE', [
        haystack,
        Constant(replacement.key),
        Constant(replacement.value),
      ]);
    }
    for (final replacement in sqlStripReplacements) {
      haystack = FunctionCallExpression<String>('REPLACE', [
        haystack,
        Constant(replacement.key),
        Constant(replacement.value),
      ]);
    }
    return haystack;
  }

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

  /// Applies a full track snapshot while preserving optimistic edits.
  ///
  /// Reads pending writes and affected cached rows inside this transaction:
  /// server metadata applies for every row, the newest pending favorite
  /// wins for edited tracks, cached rows absent from the snapshot are
  /// retained while a pending favorite or playlist reference names them,
  /// and unprotected rows accept the snapshot (including deletion).
  /// Pending additions are never appended to server membership and nothing
  /// is deduplicated by track id, so repeated application is idempotent.
  Future<void> applyLibraryTracks(List<TracksCompanion> rows) => transaction(
    () async {
      final pendingFavorites = await _pendingFavoriteValues();
      final pendingReferences = await _pendingPlaylistTrackIds();
      final incomingIds = {for (final row in rows) row.id.value};
      for (final row in rows) {
        final favorite = pendingFavorites[row.id.value];
        if (favorite == null) {
          await into(tracks).insertOnConflictUpdate(row);
        } else {
          await into(tracks)
              .insertOnConflictUpdate(row.copyWith(favorite: Value(favorite)));
        }
      }
      final cached = await (select(
        tracks,
      )..where((row) => row.id.isNotIn(incomingIds))).get();
      for (final row in cached) {
        if (pendingFavorites.containsKey(row.id)) continue;
        if (pendingReferences.contains(row.id)) continue;
        await (delete(tracks)..where((r) => r.id.equals(row.id))).go();
      }
    },
  );

  /// Applies a history response as a partial upsert with favorite
  /// protection. An empty history response never clears tracks.
  Future<void> applyHistoryTracks(List<TracksCompanion> rows) => transaction(
    () async {
      if (rows.isEmpty) return;
      final pendingFavorites = await _pendingFavoriteValues();
      for (final row in rows) {
        final favorite = pendingFavorites[row.id.value];
        if (favorite == null) {
          await into(tracks).insertOnConflictUpdate(row);
        } else {
          await into(tracks)
              .insertOnConflictUpdate(row.copyWith(favorite: Value(favorite)));
        }
      }
    },
  );

  /// Applies a playlist snapshot while preserving optimistic membership.
  ///
  /// Playlists with pending additions keep their current optimistic
  /// `trackIds` list exactly (server metadata still updates); cached
  /// playlists absent from the snapshot are retained while additions are
  /// pending. Playlists without pending additions accept server membership
  /// exactly, including legitimate duplicates.
  Future<void> applyLibraryPlaylists(List<PlaylistsCompanion> rows) =>
      transaction(() async {
        final pendingPlaylists = await _pendingPlaylistIds();
        final incomingIds = {for (final row in rows) row.id.value};
        for (final row in rows) {
          if (!pendingPlaylists.contains(row.id.value)) {
            await into(playlists).insertOnConflictUpdate(row);
            continue;
          }
          final cached = await (select(
            playlists,
          )..where((r) => r.id.equals(row.id.value))).getSingleOrNull();
          if (cached == null) {
            await into(playlists).insertOnConflictUpdate(row);
          } else {
            await into(playlists).insertOnConflictUpdate(
              row.copyWith(trackIds: Value(cached.trackIds)),
            );
          }
        }
        final cached = await (select(
          playlists,
        )..where((row) => row.id.isNotIn(incomingIds))).get();
        for (final row in cached) {
          if (pendingPlaylists.contains(row.id)) continue;
          await (delete(playlists)..where((r) => r.id.equals(row.id))).go();
        }
      });

  /// Newest pending favorite value per track, oldest first so repeats keep
  /// the latest edit.
  Future<Map<String, bool>> _pendingFavoriteValues() async {
    final operations =
        await customSelect(
              'SELECT * FROM pending_writes WHERE kind = ? ORDER BY rowid ASC',
              variables: [Variable('favorite')],
              readsFrom: {pendingWrites},
            )
            .map(
              (row) => PendingWrite(
                id: row.read<String>('id'),
                kind: row.read<String>('kind'),
                targetId: row.read<String>('target_id'),
                payload: row.read<String>('payload'),
                createdAt: row.read<DateTime>('created_at'),
                attempts: row.read<int>('attempts'),
              ),
            )
            .get();
    final values = <String, bool>{};
    for (final operation in operations) {
      try {
        final payload = jsonDecode(operation.payload) as Map<String, dynamic>?;
        final favorite = payload?['favorite'];
        if (favorite is bool) values[operation.targetId] = favorite;
      } catch (_) {}
    }
    return values;
  }

  /// Track ids named in pending playlist-addition payloads.
  Future<Set<String>> _pendingPlaylistTrackIds() async {
    final operations = await (select(
      pendingWrites,
    )..where((row) => row.kind.equals('playlistAdd'))).get();
    final ids = <String>{};
    for (final operation in operations) {
      try {
        final payload = jsonDecode(operation.payload) as Map<String, dynamic>?;
        final trackId = payload?['trackId'];
        if (trackId is String) ids.add(trackId);
      } catch (_) {}
    }
    return ids;
  }

  /// Playlist ids with pending additions.
  Future<Set<String>> _pendingPlaylistIds() async {
    final operations = await (select(
      pendingWrites,
    )..where((row) => row.kind.equals('playlistAdd'))).get();
    return {for (final operation in operations) operation.targetId};
  }

  Future<void> removeTracksExcept(List<String> ids) async {
    if (ids.isEmpty) {
      await delete(tracks).go();
      return;
    }
    await (delete(tracks)..where((track) => track.id.isNotIn(ids))).go();
  }

  Future<void> removeTrack(String id) => transaction(() async {
    await (delete(tracks)..where((track) => track.id.equals(id))).go();
    await (delete(
      pendingWrites,
    )..where((write) => write.targetId.equals(id))).go();
    // A removed track also drops queued playlist additions whose decoded
    // payload names it, not just rows targeted at it.
    final additions = await (select(
      pendingWrites,
    )..where((row) => row.kind.equals('playlistAdd'))).get();
    for (final addition in additions) {
      Map<String, dynamic>? payload;
      try {
        payload = jsonDecode(addition.payload) as Map<String, dynamic>?;
      } catch (_) {
        continue;
      }
      if (payload?['trackId'] != id) continue;
      await (delete(
        pendingWrites,
      )..where((row) => row.id.equals(addition.id))).go();
    }
    final storedPlaylists = await select(playlists).get();
    for (final playlist in storedPlaylists) {
      final ids = (jsonDecode(playlist.trackIds) as List<dynamic>)
          .cast<String>();
      if (!ids.contains(id)) continue;
      ids.removeWhere((trackId) => trackId == id);
      await (update(playlists)..where((row) => row.id.equals(playlist.id)))
          .write(PlaylistsCompanion(trackIds: Value(jsonEncode(ids))));
    }
  });

  Future<void> removePlaylist(String id) => transaction(() async {
    await (delete(
      pendingWrites,
    )..where((write) => write.targetId.equals(id))).go();
    await (delete(playlists)..where((row) => row.id.equals(id))).go();
  });

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
            id: newPendingWriteId('favorite', trackId),
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

  Stream<Map<String, DateTime>> watchAlbumDates() => select(albumDates)
      .watch()
      .map((rows) => {for (final row in rows) row.albumId: row.premiereDate});

  Future<void> replaceAlbumDates(List<AlbumDatesCompanion> rows) =>
      transaction(() async {
        await delete(albumDates).go();
        await batch((batch) => batch.insertAll(albumDates, rows));
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
            id: newPendingWriteId('playlistAdd', playlistId),
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

  /// Oldest pending operation in SQLite rowid insertion order.
  ///
  /// Delivery order must follow insertion, not lexical ids or timestamps
  /// alone; no schema change is needed for this rowid table.
  Future<PendingWrite?> nextPendingOperation() =>
      customSelect(
            'SELECT * FROM pending_writes ORDER BY rowid ASC LIMIT 1',
            readsFrom: {pendingWrites},
          )
          .map(
            (row) => PendingWrite(
              id: row.read<String>('id'),
              kind: row.read<String>('kind'),
              targetId: row.read<String>('target_id'),
              payload: row.read<String>('payload'),
              createdAt: row.read<DateTime>('created_at'),
              attempts: row.read<int>('attempts'),
            ),
          )
          .getSingleOrNull();

  Future<PendingWrite?> pendingOperationById(String id) => (select(
    pendingWrites,
  )..where((row) => row.id.equals(id))).getSingleOrNull();

  Future<bool> hasPendingOperations() async =>
      await nextPendingOperation() != null;

  /// Deletes pending `playlistAdd` rows whose decoded payload names
  /// [trackId], not just rows whose `targetId` equals it.
  Future<void> deletePendingPlaylistReferences(String trackId) =>
      transaction(() async {
        final additions = await (select(
          pendingWrites,
        )..where((row) => row.kind.equals('playlistAdd'))).get();
        for (final addition in additions) {
          Map<String, dynamic>? payload;
          try {
            payload = jsonDecode(addition.payload) as Map<String, dynamic>?;
          } catch (_) {
            continue;
          }
          if (payload?['trackId'] != trackId) continue;
          await (delete(
            pendingWrites,
          )..where((row) => row.id.equals(addition.id))).go();
        }
      });

  Future<void> completePending(String id) =>
      (delete(pendingWrites)..where((row) => row.id.equals(id))).go();

  Future<void> incrementPendingAttempts(String id) => customUpdate(
    'UPDATE pending_writes SET attempts = attempts + 1 WHERE id = ?',
    variables: [Variable(id)],
    updates: {pendingWrites},
  );

  Stream<List<Download>> watchDownloads() => select(downloads).watch();

  Future<List<Download>> allDownloads() => select(downloads).get();

  Future<void> putDownload(DownloadsCompanion row) =>
      into(downloads).insertOnConflictUpdate(row);

  Future<void> queueDownloads(Iterable<String> trackIds) async {
    final rows = trackIds
        .map(
          (trackId) => DownloadsCompanion.insert(
            trackId: trackId,
            status: 'queued',
            error: const Value(null),
          ),
        )
        .toList(growable: false);
    if (rows.isEmpty) return;
    await batch((batch) => batch.insertAllOnConflictUpdate(downloads, rows));
  }

  Future<void> failQueuedDownloads(String message) =>
      (update(downloads)..where((row) => row.status.equals('queued'))).write(
        DownloadsCompanion(
          status: const Value('failed'),
          error: Value(message),
        ),
      );

  Future<void> removeDownload(String trackId) =>
      (delete(downloads)..where((row) => row.trackId.equals(trackId))).go();

  Future<void> clearDownloads() => delete(downloads).go();

  Stream<List<DowntifyImport>> watchDowntifyImports(
    String serverId,
    String userId,
  ) =>
      (select(downtifyImports)
            ..where(
              (row) =>
                  row.jellyfinServerId.equals(serverId) &
                  row.jellyfinUserId.equals(userId),
            )
            ..orderBy([(row) => OrderingTerm.desc(row.updatedAt)]))
          .watch();

  Future<List<DowntifyImport>> getDowntifyImports(
    String serverId,
    String userId,
  ) =>
      (select(downtifyImports)..where(
            (row) =>
                row.jellyfinServerId.equals(serverId) &
                row.jellyfinUserId.equals(userId),
          ))
          .get();

  Future<void> putDowntifyImport(DowntifyImportsCompanion row) =>
      into(downtifyImports).insertOnConflictUpdate(row);

  Future<void> removeDowntifyImport(String id) =>
      (delete(downtifyImports)..where((row) => row.id.equals(id))).go();

  Future<DowntifyImport?> getDowntifyImport(String id) => (select(
    downtifyImports,
  )..where((row) => row.id.equals(id))).getSingleOrNull();

  /// Scoped conditional import update: only the row matching id, Jellyfin
  /// account, and origin is touched. Returns the affected-row count; zero
  /// rows means stale or removed work, never permission to recreate the
  /// row. Updates never insert a deleted row.
  Future<int> updateDowntifyImportWhere({
    required String id,
    required String jellyfinServerId,
    required String jellyfinUserId,
    required String origin,
    required DowntifyImportsCompanion values,
  }) =>
      (update(downtifyImports)..where(
            (row) =>
                row.id.equals(id) &
                row.jellyfinServerId.equals(jellyfinServerId) &
                row.jellyfinUserId.equals(jellyfinUserId) &
                row.downtifyUrl.equals(origin),
          ))
          .write(values);

  /// Scoped conditional import removal with the same predicates.
  Future<int> removeDowntifyImportWhere({
    required String id,
    required String jellyfinServerId,
    required String jellyfinUserId,
    required String origin,
  }) =>
      (delete(downtifyImports)..where(
            (row) =>
                row.id.equals(id) &
                row.jellyfinServerId.equals(jellyfinServerId) &
                row.jellyfinUserId.equals(jellyfinUserId) &
                row.downtifyUrl.equals(origin),
          ))
          .go();

  Future<void> clearAccountData() => transaction(() async {
    await delete(pendingWrites).go();
    await delete(downloads).go();
    await delete(playlists).go();
    await delete(albumDates).go();
    await delete(downtifyImports).go();
    await delete(tracks).go();
  });
}
