import 'dart:async';

import '../../../storage/database.dart';
import '../account_scope.dart';
import '../jellyfin_client.dart';
import '../session.dart';
import 'library_refresh_result.dart';
import 'pending_edit_delivery.dart';

/// Single owner of Jellyfin library effects and server operations.
///
/// Injected with the client, database, and account scope; imports no
/// provider or widget code. [AppController] keeps its public action
/// signatures and delegates library work through its current lease, while
/// this module supplies one ordered server-operation lane per account,
/// explicit refresh outcomes, and immediate optimistic local edits.
class JellyfinLibrary {
  JellyfinLibrary(this._client, this._database, this._scope)
    : _delivery = PendingEditDelivery(_client, _database, _scope);

  final JellyfinClient _client;
  final AppDatabase _database;
  final AccountScope _scope;
  final PendingEditDelivery _delivery;

  /// Server-operation lanes keyed by account generation/owner (never the
  /// lease object's identity, so a same-account metadata refresh keeps the
  /// same lane for its new immutable lease).
  final Map<String, Future<void>> _lanes = {};

  /// One running drain per lane; repeated requests join it.
  final Map<String, Future<bool>> _drains = {};

  /// Edit wake-ups observed while a drain runs.
  final Map<String, bool> _drainWake = {};

  String _laneKey(AccountLease lease) =>
      '${lease.generation}|${lease.ownerKey}';

  /// Full library refresh: pending delivery, then playlist, track, and
  /// album-date snapshots, returning the effective committed catalog.
  Future<LibraryRefreshResult> refresh(AccountLease lease) =>
      _inLane(lease, () => _refreshNow(lease));

  /// Track-only refresh for import matching. Reads and commits tracks only;
  /// triggers no playback, downloads, car, or remote/Cast setup.
  Future<LibraryRefreshResult> refreshTracks(AccountLease lease) =>
      _inLane(lease, () => _refreshTracksNow(lease));

  /// Recently-played refresh. Partial upsert; an empty history response
  /// never clears tracks.
  Future<LibraryRefreshResult> refreshHistory(
    AccountLease lease, {
    int limit = 100,
  }) => _inLane(lease, () => _refreshHistoryNow(lease, limit: limit));

  /// Optimistic favorite edit: commits locally through the fence
  /// immediately (even while a server request is pending), then drains.
  Future<void> toggleFavorite(
    AccountLease lease,
    String trackId,
    bool favorite,
  ) async {
    final applied = await _scope.commit(
      lease,
      () => _database.saveFavoriteEdit(trackId, favorite),
    );
    if (applied == AccountWriteResult.stale) return;
    if (!_scope.isCurrent(lease)) return;
    _noteLocalEdit(lease);
    await requestDrain(lease);
  }

  /// Optimistic playlist addition: commits locally immediately, then drains.
  /// Membership is appended locally without a playlist refetch.
  Future<void> addToPlaylist(
    AccountLease lease,
    String playlistId,
    String trackId,
  ) async {
    final applied = await _scope.commit(
      lease,
      () => _database.savePlaylistAddition(playlistId, trackId),
    );
    if (applied == AccountWriteResult.stale) return;
    if (!_scope.isCurrent(lease)) return;
    _noteLocalEdit(lease);
    await requestDrain(lease);
  }

  Future<void> createPlaylist(
    AccountLease lease,
    String name,
    List<String> trackIds,
  ) async {
    final session = lease.session;
    await _client.createPlaylist(session, name.trim(), trackIds);
    if (!_scope.isCurrent(lease)) return;
    await _refetchPlaylists(lease, session);
  }

  Future<void> renamePlaylist(
    AccountLease lease,
    String playlistId,
    String name,
  ) async {
    if (!_scope.isCurrent(lease)) return;
    final session = lease.session;
    await _client.renamePlaylist(session, playlistId, name.trim());
    if (!_scope.isCurrent(lease)) return;
    await _refetchPlaylists(lease, session);
  }

  Future<void> deletePlaylist(AccountLease lease, String playlistId) async {
    if (!_scope.isCurrent(lease)) return;
    final session = lease.session;
    await _inLane(lease, () async {
      if (!_scope.isCurrent(lease)) return;
      await _client.deleteItem(session, playlistId);
      if (!_scope.isCurrent(lease)) return;
      await _scope.commit(lease, () => _database.removePlaylist(playlistId));
    });
  }

  Future<void> deleteTrack(AccountLease lease, String trackId) async {
    if (!_scope.isCurrent(lease)) return;
    final session = lease.session;
    await _inLane(lease, () async {
      if (!_scope.isCurrent(lease)) return;
      await _client.deleteItem(session, trackId);
      if (!_scope.isCurrent(lease)) return;
      await _scope.commit(lease, () => _database.removeTrack(trackId));
    });
  }

  /// Orders one drain per lane; repeated requests join the running drain. A
  /// new-edit wake-up during an empty-read/completion race causes the
  /// current drain or a follow-up drain to read again.
  Future<bool> requestDrain(AccountLease lease) {
    final key = _laneKey(lease);
    final running = _drains[key];
    if (running != null) {
      return running.then((_) {
        if (!_scope.isCurrent(lease)) return false;
        if (_drainWake[key] == true) return requestDrain(lease);
        return false;
      });
    }
    final future = _inLaneKey(key, () => _drainNow(lease));
    _drains[key] = future;
    future.whenComplete(() {
      if (identical(_drains[key], future)) _drains.remove(key);
    });
    return future;
  }

  /// Marks a locally committed edit so the running (or next) drain reads
  /// again even if it just observed an empty queue.
  void _noteLocalEdit(AccountLease lease) {
    _drainWake[_laneKey(lease)] = true;
  }

  /// Private drain: runs inside the lane without recursively acquiring it.
  /// Reads the next currently pending operation immediately before
  /// delivery; after each result, reads again. Returns when the queue is
  /// empty, delivery blocks, or the lease goes stale.
  Future<bool> _drainNow(AccountLease lease) async {
    final key = _laneKey(lease);
    var deliveredAll = true;
    while (_scope.isCurrent(lease)) {
      _drainWake[key] = false;
      final empty = !(await _database.hasPendingOperations());
      if (empty) {
        if (_drainWake[key] == true) continue;
        break;
      }
      final outcome = await _delivery.deliverNext(lease);
      if (outcome == PendingDelivery.stale) return false;
      if (outcome == PendingDelivery.blocked) {
        deliveredAll = false;
        break;
      }
    }
    return deliveredAll && _scope.isCurrent(lease);
  }

  Future<LibraryRefreshResult> _refreshNow(AccountLease lease) async {
    if (!_scope.isCurrent(lease)) return const LibraryRefreshResult.stale();
    final session = lease.session;
    final delivered = await _drainNow(lease);
    if (!_scope.isCurrent(lease)) return const LibraryRefreshResult.stale();
    Object? playlistError;
    try {
      final playlists = await _client.fetchPlaylists(session);
      if (!_scope.isCurrent(lease)) {
        return const LibraryRefreshResult.stale();
      }
      final applied = await _scope.commit(
        lease,
        () => _database.replacePlaylists(playlists),
      );
      if (applied == AccountWriteResult.stale) {
        return const LibraryRefreshResult.stale();
      }
    } catch (error) {
      if (!_scope.isCurrent(lease)) {
        return const LibraryRefreshResult.stale();
      }
      playlistError = error;
    }
    try {
      final tracks = await _client.fetchTracks(session);
      if (!_scope.isCurrent(lease)) {
        return const LibraryRefreshResult.stale();
      }
      final applied = await _scope.commit(
        lease,
        () => _database.replaceTracks(tracks),
      );
      if (applied == AccountWriteResult.stale) {
        return const LibraryRefreshResult.stale();
      }
    } catch (error) {
      if (!_scope.isCurrent(lease)) {
        return const LibraryRefreshResult.stale();
      }
      return LibraryRefreshResult.failed(error);
    }
    if (!_scope.isCurrent(lease)) return const LibraryRefreshResult.stale();
    try {
      final albumDates = await _client.fetchAlbumDates(session);
      if (!_scope.isCurrent(lease)) {
        return const LibraryRefreshResult.stale();
      }
      await _scope.commit(lease, () => _database.replaceAlbumDates(albumDates));
    } catch (_) {
      if (!_scope.isCurrent(lease)) {
        return const LibraryRefreshResult.stale();
      }
    }
    if (!_scope.isCurrent(lease)) return const LibraryRefreshResult.stale();
    // Wake pending delivery after the snapshot stage without a recursive
    // lane lock or an immediate retry loop after a failed send.
    if (!delivered) _noteLocalEdit(lease);
    final catalog = await _database.allTracks();
    if (!_scope.isCurrent(lease)) return const LibraryRefreshResult.stale();
    return LibraryRefreshResult.committed(
      catalog,
      pendingBlocked: !delivered,
      playlistError: playlistError,
    );
  }

  Future<LibraryRefreshResult> _refreshTracksNow(AccountLease lease) async {
    if (!_scope.isCurrent(lease)) return const LibraryRefreshResult.stale();
    final session = lease.session;
    final delivered = await _drainNow(lease);
    if (!_scope.isCurrent(lease)) return const LibraryRefreshResult.stale();
    try {
      final tracks = await _client.fetchTracks(session);
      if (!_scope.isCurrent(lease)) {
        return const LibraryRefreshResult.stale();
      }
      final applied = await _scope.commit(
        lease,
        () => _database.replaceTracks(tracks),
      );
      if (applied == AccountWriteResult.stale) {
        return const LibraryRefreshResult.stale();
      }
    } catch (error) {
      if (!_scope.isCurrent(lease)) {
        return const LibraryRefreshResult.stale();
      }
      return LibraryRefreshResult.failed(error);
    }
    if (!_scope.isCurrent(lease)) return const LibraryRefreshResult.stale();
    if (!delivered) _noteLocalEdit(lease);
    final catalog = await _database.allTracks();
    if (!_scope.isCurrent(lease)) return const LibraryRefreshResult.stale();
    return LibraryRefreshResult.committed(catalog, pendingBlocked: !delivered);
  }

  Future<LibraryRefreshResult> _refreshHistoryNow(
    AccountLease lease, {
    required int limit,
  }) async {
    if (!_scope.isCurrent(lease)) return const LibraryRefreshResult.stale();
    final session = lease.session;
    late final List<TracksCompanion> rows;
    try {
      rows = await _client.fetchRecentlyPlayed(session, limit: limit);
    } catch (error) {
      if (!_scope.isCurrent(lease)) {
        return const LibraryRefreshResult.stale();
      }
      return LibraryRefreshResult.failed(error);
    }
    if (!_scope.isCurrent(lease)) return const LibraryRefreshResult.stale();
    if (rows.isEmpty) return const LibraryRefreshResult.committed([]);
    await _scope.commit(lease, () => _database.upsertTracks(rows));
    if (!_scope.isCurrent(lease)) return const LibraryRefreshResult.stale();
    return const LibraryRefreshResult.committed([]);
  }

  Future<void> _refetchPlaylists(
    AccountLease lease,
    JellyfinSession session,
  ) async {
    await _inLane(lease, () async {
      if (!_scope.isCurrent(lease)) return;
      final playlists = await _client.fetchPlaylists(session);
      if (!_scope.isCurrent(lease)) return;
      await _scope.commit(lease, () => _database.replacePlaylists(playlists));
    });
  }

  Future<T> _inLane<T>(AccountLease lease, Future<T> Function() work) =>
      _inLaneKey(_laneKey(lease), work);

  Future<T> _inLaneKey<T>(String key, Future<T> Function() work) {
    final previous = _lanes[key] ?? Future<void>.value();
    final result = previous.then((_) => work());
    _lanes[key] = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }
}
