import 'dart:async';
import 'dart:collection';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../platform/download_store.dart';
import '../../storage/database.dart';
import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/session.dart';

class DownloadService extends ChangeNotifier {
  DownloadService(this._database, this._client, this._store);

  static const _parallelDownloads = 3;
  static const _maximumAttempts = 3;

  final AppDatabase _database;
  final JellyfinClient _client;
  final DownloadStore _store;
  final Set<String> _active = {};
  final Set<String> _pending = {};
  final Set<String> _cancelled = {};
  final Queue<_DownloadTask> _queue = Queue();
  int _workers = 0;
  int _generation = 0;
  bool _disposed = false;

  bool isActive(String trackId) => _active.contains(trackId);

  Future<void> download(
    JellyfinSession session,
    Track track, {
    bool small = false,
  }) => downloadAll(session, [track], small: small);

  Future<void> downloadAll(
    JellyfinSession session,
    Iterable<Track> tracks, {
    bool small = false,
  }) async {
    final existing = {
      for (final row in await _database.allDownloads()) row.trackId: row,
    };
    final generation = _generation;
    final tasks = <_DownloadTask>[];
    for (final track in tracks) {
      if (existing[track.id]?.status == 'complete' ||
          _active.contains(track.id) ||
          !_pending.add(track.id)) {
        continue;
      }
      _cancelled.remove(track.id);
      tasks.add(_DownloadTask(session, track, small, generation));
    }
    if (tasks.isEmpty) return;
    await _database.queueDownloads(tasks.map((task) => task.track.id));
    _queue.addAll(tasks);
    _startWorkers();
  }

  Future<void> resume(
    JellyfinSession session,
    Iterable<Track> orderedTracks, {
    bool small = false,
  }) async {
    final downloads = {
      for (final row in await _database.allDownloads()) row.trackId: row,
    };
    await downloadAll(
      session,
      orderedTracks.where((track) {
        final status = downloads[track.id]?.status;
        return status != null && status != 'complete';
      }),
      small: small,
    );
  }

  void _startWorkers() {
    while (_workers < _parallelDownloads && _queue.isNotEmpty) {
      _workers++;
      unawaited(_work());
    }
  }

  Future<void> _work() async {
    try {
      while (_queue.isNotEmpty) {
        final task = _queue.removeFirst();
        _pending.remove(task.track.id);
        if (task.generation != _generation) continue;
        await _run(task);
      }
    } finally {
      _workers--;
      _startWorkers();
    }
  }

  Future<void> _run(_DownloadTask task) async {
    if (!_active.add(task.track.id)) return;
    _notifyChanged();
    try {
      await _database.putDownload(
        DownloadsCompanion.insert(
          trackId: task.track.id,
          status: 'downloading',
        ),
      );
      if (_isCancelled(task)) return;
      Object? lastError;
      for (var attempt = 1; attempt <= _maximumAttempts; attempt++) {
        if (_isCancelled(task)) return;
        try {
          final localUri = await _save(task);
          if (_isCancelled(task)) {
            await _store.remove(localUri);
            return;
          }
          await _database.putDownload(
            DownloadsCompanion.insert(
              trackId: task.track.id,
              status: 'complete',
              localUri: Value(localUri),
            ),
          );
          return;
        } catch (error) {
          lastError = error;
          if (!_isCancelled(task) && attempt < _maximumAttempts) {
            await Future<void>.delayed(Duration(seconds: attempt));
          }
        }
      }
      if (!_isCancelled(task)) {
        await _database.putDownload(
          DownloadsCompanion.insert(
            trackId: task.track.id,
            status: 'failed',
            error: Value(lastError.toString()),
          ),
        );
      }
    } finally {
      _active.remove(task.track.id);
      _notifyChanged();
    }
  }

  Future<String> _save(_DownloadTask task) => _store.save(
    task.session.serverId,
    task.track.id,
    _client.downloadUri(task.session, task.track.id, small: task.small),
    _client.downloadHeaders(task.session),
    task.small ? 'm4a' : task.track.container,
  );

  bool _isCancelled(_DownloadTask task) =>
      task.generation != _generation || _cancelled.contains(task.track.id);

  void _notifyChanged() {
    if (!_disposed) notifyListeners();
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
    _cancelled.add(trackId);
    _pending.remove(trackId);
    _queue.removeWhere((task) => task.track.id == trackId);
    final row = await (_database.select(
      _database.downloads,
    )..where((row) => row.trackId.equals(trackId))).getSingleOrNull();
    if (row?.localUri != null) await _store.remove(row!.localUri!);
    await _database.removeDownload(trackId);
  }

  Future<void> clear() async {
    _generation++;
    _pending.clear();
    _cancelled.clear();
    _queue.clear();
    final rows = await _database.select(_database.downloads).get();
    for (var start = 0; start < rows.length; start += 8) {
      final end = start + 8 < rows.length ? start + 8 : rows.length;
      await Future.wait(
        rows
            .sublist(start, end)
            .where((row) => row.localUri != null)
            .map((row) => _removeFile(row.localUri!)),
      );
    }
    await _database.clearDownloads();
  }

  Future<void> _removeFile(String localUri) async {
    try {
      await _store.remove(localUri);
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _queue.clear();
    _store.dispose();
    super.dispose();
  }
}

class _DownloadTask {
  const _DownloadTask(this.session, this.track, this.small, this.generation);

  final JellyfinSession session;
  final Track track;
  final bool small;
  final int generation;
}
