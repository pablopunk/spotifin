import 'dart:async';
import 'dart:collection';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../platform/download_store.dart';
import '../../platform/artwork_store.dart';
import '../../storage/database.dart';
import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/session.dart';
import '../redaction.dart';

class DownloadService extends ChangeNotifier {
  DownloadService(this._database, this._client, this._store, this._artwork);

  static const _parallelDownloads = 3;
  static const _maximumAttempts = 3;

  final AppDatabase _database;
  final JellyfinClient _client;
  final DownloadStore _store;
  final ArtworkStore _artwork;
  final Set<String> _active = {};
  final Set<String> _pending = {};
  final Set<String> _cancelled = {};
  final Queue<_DownloadTask> _queue = Queue();
  int _workers = 0;
  int _generation = 0;
  int _consecutiveFailures = 0;
  bool _disposed = false;
  bool _clearing = false;
  bool _pausing = false;
  bool _suspending = false;
  bool _paused = false;
  Completer<void>? _idleCompleter;
  Future<void>? _clearFuture;
  Future<void>? _suspendFuture;
  JellyfinSession? _latestSession;

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
    if (_clearing || _pausing || _suspending || _disposed) return;
    _latestSession = session;
    _paused = false;
    _consecutiveFailures = 0;
    await _enqueue(session, tracks, small: small);
  }

  Future<void> _enqueue(
    JellyfinSession session,
    Iterable<Track> tracks, {
    required bool small,
  }) async {
    final existing = {
      for (final row in await _database.allDownloads()) row.trackId: row,
    };
    if (_clearing || _pausing || _suspending || _disposed) return;
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
    if (tasks.isEmpty) {
      _startWorkers();
      return;
    }
    await _database.queueDownloads(tasks.map((task) => task.track.id));
    final cancelled = tasks
        .where((task) => _isCancelled(task) || _clearing || _disposed)
        .toList(growable: false);
    for (final task in cancelled) {
      _pending.remove(task.track.id);
      await _database.removeDownload(task.track.id);
    }
    _queue.addAll(tasks.where((task) => !cancelled.contains(task)));
    _startWorkers();
  }

  Future<void> resume(
    JellyfinSession session,
    Iterable<Track> orderedTracks, {
    bool small = false,
  }) async {
    if (_clearing || _pausing || _suspending || _disposed) return;
    _latestSession = session;
    final downloads = {
      for (final row in await _database.allDownloads()) row.trackId: row,
    };
    await _enqueue(
      session,
      orderedTracks.where((track) {
        final status = downloads[track.id]?.status;
        return status == 'queued' || status == 'downloading';
      }),
      small: small,
    );
  }

  void _startWorkers() {
    while (!_paused &&
        !_clearing &&
        _workers < _parallelDownloads &&
        _queue.isNotEmpty) {
      _workers++;
      unawaited(_work());
    }
  }

  Future<void> _work() async {
    try {
      while (!_paused && !_clearing && _queue.isNotEmpty) {
        final task = _queue.removeFirst();
        _pending.remove(task.track.id);
        if (task.generation != _generation) continue;
        try {
          await _run(task);
        } catch (error) {
          try {
            await _recordFailure(task, error);
          } catch (_) {}
          try {
            await _pauseAfterRepeatedFailures();
          } catch (_) {}
        }
      }
    } finally {
      _workers--;
      if (_active.isEmpty && !(_idleCompleter?.isCompleted ?? true)) {
        _idleCompleter?.complete();
      }
      _startWorkers();
    }
  }

  Future<void> _run(_DownloadTask task) async {
    if (_isCancelled(task) || !_active.add(task.track.id)) return;
    _notifyChanged();
    try {
      await _database.putDownload(
        DownloadsCompanion.insert(
          trackId: task.track.id,
          status: 'downloading',
          error: const Value(null),
        ),
      );
      if (_isCancelled(task)) {
        await _database.removeDownload(task.track.id);
        return;
      }
      Object? lastError;
      String? localUri;
      for (var attempt = 1; attempt <= _maximumAttempts; attempt++) {
        if (_isCancelled(task)) return;
        try {
          localUri = await _save(task);
          break;
        } catch (error) {
          lastError = error;
          if (_isPermanentTrackFailure(error)) break;
          if (!_isCancelled(task) && attempt < _maximumAttempts) {
            await Future<void>.delayed(Duration(seconds: attempt));
          }
        }
      }
      if (_isCancelled(task)) {
        if (localUri != null) await _store.remove(localUri);
        return;
      }
      if (localUri == null) {
        await _recordFailure(
          task,
          lastError,
          affectsQueue: !_isPermanentTrackFailure(lastError),
        );
        if (lastError is DownloadStoreException &&
            lastError.statusCode == 401) {
          await _pauseAfterRepeatedFailures();
        }
        return;
      }
      await _finishDownload(task, localUri);
    } finally {
      _active.remove(task.track.id);
      _notifyChanged();
    }
  }

  Future<void> _finishDownload(_DownloadTask task, String localUri) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _maximumAttempts; attempt++) {
      try {
        await _database.putDownload(
          DownloadsCompanion.insert(
            trackId: task.track.id,
            status: 'complete',
            localUri: Value(localUri),
            error: const Value(null),
          ),
        );
        if (_isCancelled(task)) {
          await _store.remove(localUri);
          await _database.removeDownload(task.track.id);
          return;
        }
        _consecutiveFailures = 0;
        unawaited(_cacheArtwork(task));
        return;
      } catch (error) {
        lastError = error;
        if (attempt < _maximumAttempts) {
          await Future<void>.delayed(Duration(seconds: attempt));
        }
      }
    }
    await _store.remove(localUri);
    throw lastError!;
  }

  Future<void> _recordFailure(
    _DownloadTask task,
    Object? error, {
    bool affectsQueue = true,
  }) async {
    if (_isCancelled(task)) return;
    await _database.putDownload(
      DownloadsCompanion.insert(
        trackId: task.track.id,
        status: 'failed',
        error: Value(redactSecrets(error)),
      ),
    );
    if (affectsQueue) _consecutiveFailures++;
    if (affectsQueue && _consecutiveFailures >= _parallelDownloads) {
      await _pauseAfterRepeatedFailures();
    }
  }

  bool _isPermanentTrackFailure(Object? error) =>
      error is DownloadStoreException &&
      !error.isRetryable &&
      error.statusCode != 401;

  Future<String> _save(_DownloadTask task) => _store.save(
    '${_sessionFor(task).serverId}.${_sessionFor(task).userId}',
    task.track.id,
    _client.downloadUri(_sessionFor(task), task.track.id, small: task.small),
    _client.downloadHeaders(_sessionFor(task)),
    task.small ? 'm4a' : task.track.container,
  );

  Future<void> _cacheArtwork(_DownloadTask task) async {
    final session = _sessionFor(task);
    final accountId = '${session.serverId}.${session.userId}';
    final itemId = task.track.albumId ?? task.track.id;
    await Future.wait([
      for (final width in [128, 512, 1024])
        _artwork.resolve(
          accountId,
          itemId,
          width,
          _client.imageUri(session, itemId, width: width),
        ),
    ]);
  }

  JellyfinSession _sessionFor(_DownloadTask task) {
    final latest = _latestSession;
    return latest?.serverId == task.session.serverId &&
            latest?.userId == task.session.userId
        ? latest!
        : task.session;
  }

  bool _isCancelled(_DownloadTask task) =>
      task.generation != _generation || _cancelled.contains(task.track.id);

  void _notifyChanged() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _pauseAfterRepeatedFailures() async {
    if (_paused || _pausing) return;
    _pausing = true;
    _paused = true;
    for (final task in _queue) {
      _pending.remove(task.track.id);
    }
    _queue.clear();
    try {
      await _database.failQueuedDownloads(
        'Download queue paused after repeated errors. Try again when the '
        'connection is available.',
      );
    } finally {
      _pausing = false;
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
    _cancelled.add(trackId);
    _pending.remove(trackId);
    _queue.removeWhere((task) => task.track.id == trackId);
    final row = await (_database.select(
      _database.downloads,
    )..where((row) => row.trackId.equals(trackId))).getSingleOrNull();
    if (row?.localUri != null) await _store.remove(row!.localUri!);
    await _database.removeDownload(trackId);
  }

  Future<void> reconcile(Iterable<String> trackIds) async {
    final valid = trackIds.toSet();
    final orphaned = (await _database.allDownloads()).where(
      (download) => !valid.contains(download.trackId),
    );
    for (final download in orphaned) {
      _cancelled.add(download.trackId);
      _pending.remove(download.trackId);
      _queue.removeWhere((task) => task.track.id == download.trackId);
      if (download.localUri != null) await _removeFile(download.localUri!);
      await _database.removeDownload(download.trackId);
    }
  }

  Future<void> suspend() {
    final current = _suspendFuture;
    if (current != null) return current;
    final clearing = _clearFuture;
    if (clearing != null) {
      return clearing.then((_) {
        _latestSession = null;
      });
    }
    return _suspendFuture = _suspend();
  }

  Future<void> _suspend() async {
    _suspending = true;
    try {
      final incomplete = (await _database.allDownloads())
          .where((download) => download.status != 'complete')
          .map((download) => download.trackId)
          .toSet();
      _generation++;
      _pending.clear();
      _queue.clear();
      _latestSession = null;
      await _waitForActiveDownloads();
      final current = {
        for (final download in await _database.allDownloads())
          download.trackId: download.status,
      };
      await _database.queueDownloads(
        incomplete.where((trackId) => current[trackId] != 'complete'),
      );
    } finally {
      _suspending = false;
      _suspendFuture = null;
    }
  }

  Future<void> clear() {
    final current = _clearFuture;
    if (current != null) return current;
    final suspending = _suspendFuture;
    if (suspending != null) return suspending.then((_) => clear());
    return _clearFuture = _clear();
  }

  Future<void> _clear() async {
    _clearing = true;
    try {
      _generation++;
      _pending.clear();
      _cancelled.clear();
      _queue.clear();
      await _waitForActiveDownloads();
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
    } finally {
      _clearing = false;
      _clearFuture = null;
      _notifyChanged();
    }
  }

  Future<void> _waitForActiveDownloads() async {
    if (_active.isEmpty) return;
    _idleCompleter = Completer<void>();
    await _idleCompleter!.future;
    _idleCompleter = null;
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
