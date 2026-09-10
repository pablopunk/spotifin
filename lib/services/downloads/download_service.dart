import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../platform/download_store.dart';
import '../../storage/database.dart';
import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/session.dart';

class DownloadService extends ChangeNotifier {
  DownloadService(this._database, this._client, this._store);

  final AppDatabase _database;
  final JellyfinClient _client;
  final DownloadStore _store;
  final Set<String> _active = {};

  bool isActive(String trackId) => _active.contains(trackId);

  Future<void> download(
    JellyfinSession session,
    Track track, {
    bool small = false,
  }) async {
    if (!_active.add(track.id)) return;
    notifyListeners();
    await _database.putDownload(
      DownloadsCompanion.insert(trackId: track.id, status: 'downloading'),
    );
    try {
      final source = _client.downloadUri(session, track.id, small: small);
      final localUri = await _store.save(
        session.serverId,
        track.id,
        source,
        _client.downloadHeaders(session),
        small ? 'm4a' : track.container,
      );
      await _database.putDownload(
        DownloadsCompanion.insert(
          trackId: track.id,
          status: 'complete',
          localUri: Value(localUri),
        ),
      );
    } catch (error) {
      await _database.putDownload(
        DownloadsCompanion.insert(
          trackId: track.id,
          status: 'failed',
          error: Value(error.toString()),
        ),
      );
    } finally {
      _active.remove(track.id);
      notifyListeners();
    }
  }

  Future<Uri?> resolve(String trackId) async {
    final row = await (_database.select(
      _database.downloads,
    )..where((row) => row.trackId.equals(trackId))).getSingleOrNull();
    if (row?.status != 'complete' || row?.localUri == null) return null;
    final resolved = await _store.resolve(row!.localUri!);
    if (resolved == null) await _database.removeDownload(trackId);
    return resolved;
  }

  Future<Map<String, Uri>> resolveAll(Iterable<String> trackIds) async {
    final wanted = trackIds.toSet();
    if (wanted.isEmpty) return const {};
    final rows = await (_database.select(
      _database.downloads,
    )..where((row) => row.status.equals('complete'))).get();
    final matches = rows.where(
      (row) => wanted.contains(row.trackId) && row.localUri != null,
    );
    final entries = await Future.wait(
      matches.map((row) async {
        final uri = await _store.resolve(row.localUri!);
        if (uri == null) {
          await _database.removeDownload(row.trackId);
          return null;
        }
        return MapEntry(row.trackId, uri);
      }),
    );
    return Map.fromEntries(entries.whereType<MapEntry<String, Uri>>());
  }

  Future<void> remove(String trackId) async {
    final row = await (_database.select(
      _database.downloads,
    )..where((row) => row.trackId.equals(trackId))).getSingleOrNull();
    if (row?.localUri != null) await _store.remove(row!.localUri!);
    await _database.removeDownload(trackId);
  }

  Future<void> clear() async {
    final rows = await _database.select(_database.downloads).get();
    for (final row in rows) {
      if (row.localUri != null) await _store.remove(row.localUri!);
    }
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }
}
