import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/jellyfin/account_scope.dart';
import '../../services/jellyfin/jellyfin_client.dart';
import '../../services/jellyfin/library_cache_owner_store.dart';
import '../../services/jellyfin/secure_storage_config.dart';
import '../../services/jellyfin/session.dart';
import '../../storage/database.dart';
import '../providers.dart';
import 'development_login.dart';

enum AppStatus { starting, signedOut, ready }

class AppState {
  const AppState({
    this.status = AppStatus.starting,
    this.session,
    this.syncing = false,
    this.error,
    this.syncError,
    this.lastSyncedAt,
    this.smallStreaming = false,
    this.smallDownloads = false,
    this.normalization = false,
    this.glassEffects = true,
    this.glassOpacity = .8,
    this.cacheOwnerConflict = false,
    this.cacheOwnerMessage,
  });

  final AppStatus status;
  final JellyfinSession? session;
  final bool syncing;
  final String? error;
  final String? syncError;
  final DateTime? lastSyncedAt;
  final bool smallStreaming;
  final bool smallDownloads;
  final bool normalization;
  final bool glassEffects;
  final double glassOpacity;

  /// True when the on-device cache belongs to another account (or an unknown
  /// account) and the attempted sign-in was blocked. The app returns to the
  /// login screen until the user explicitly clears the saved library.
  final bool cacheOwnerConflict;
  final String? cacheOwnerMessage;

  AppState copyWith({
    AppStatus? status,
    JellyfinSession? session,
    bool? syncing,
    String? error,
    String? syncError,
    bool clearError = false,
    bool clearSyncError = false,
    DateTime? lastSyncedAt,
    bool clearSession = false,
    bool? smallStreaming,
    bool? smallDownloads,
    bool? normalization,
    bool? glassEffects,
    double? glassOpacity,
    bool? cacheOwnerConflict,
    String? cacheOwnerMessage,
    bool clearCacheConflict = false,
  }) => AppState(
    status: status ?? this.status,
    session: clearSession ? null : session ?? this.session,
    syncing: syncing ?? this.syncing,
    error: clearError ? null : error ?? this.error,
    syncError: clearSyncError ? null : syncError ?? this.syncError,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    smallStreaming: smallStreaming ?? this.smallStreaming,
    smallDownloads: smallDownloads ?? this.smallDownloads,
    normalization: normalization ?? this.normalization,
    glassEffects: glassEffects ?? this.glassEffects,
    glassOpacity: glassOpacity ?? this.glassOpacity,
    cacheOwnerConflict: clearCacheConflict
        ? false
        : cacheOwnerConflict ?? this.cacheOwnerConflict,
    cacheOwnerMessage: clearCacheConflict
        ? null
        : cacheOwnerMessage ?? this.cacheOwnerMessage,
  );
}

@visibleForTesting
bool withinRefreshCooldown(DateTime? lastSyncedAt, DateTime now) =>
    lastSyncedAt != null &&
    now.difference(lastSyncedAt) < const Duration(minutes: 5);

class AppController extends Notifier<AppState> {
  Future<void>? _refreshFuture;
  AccountLease? _refreshLease;
  Timer? _refreshRetryTimer;
  int _refreshRetryAttempt = 0;
  String? _remoteAccountId;
  Future<void> _lifecycle = Future.value();

  AccountScope get _scope => ref.read(accountScopeProvider);
  LibraryCacheOwnerStore get _ownerStore =>
      ref.read(libraryCacheOwnerStoreProvider);

  /// Returns the active lease, activating from [AppState.session] when a
  /// legacy test controller published a ready state without going through
  /// [signIn]/[initialize]. Production ready states always carry a lease;
  /// the fallback only keeps pre-lease unit tests (e.g. playlist mutations
  /// with a stubbed [AppController.build]) exercising the same fenced path.
  AccountLease? _leaseOrActivate() {
    final scope = _scope;
    final current = scope.current;
    if (current != null) return current;
    final session = state.session;
    if (session == null) return null;
    return scope.activate(session);
  }

  @override
  AppState build() {
    ref.onDispose(() {
      _refreshRetryTimer?.cancel();
    });
    return const AppState();
  }

  Future<T> _enqueueLifecycle<T>(Future<T> Function() work) {
    final previous = _lifecycle;
    final completer = Completer<T>();
    _lifecycle = previous.then((_) async {
      try {
        completer.complete(await work());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Future<bool> _hasCachedAccountData() async {
    final database = ref.read(databaseProvider);
    if ((await database.allTracks()).isNotEmpty) return true;
    if ((await database.pendingOperations()).isNotEmpty) return true;
    if ((await database.allDownloads()).isNotEmpty) return true;
    if ((await database.select(database.playlists).get()).isNotEmpty) {
      return true;
    }
    if ((await database.select(database.albumDates).get()).isNotEmpty) {
      return true;
    }
    if ((await database.select(database.downtifyImports).get()).isNotEmpty) {
      return true;
    }
    return false;
  }

  Future<bool> _isCacheEmpty() async => !await _hasCachedAccountData();

  static String _conflictMessageForMismatch() =>
      'This device has a saved library from a different Jellyfin account. '
      'Sign in with the original account, or clear the saved library to use '
      'this account. Clearing removes saved songs, playlists, downloads, '
      'and pending edits.';

  static String _conflictMessageForUnknown() =>
      'This device has a saved library with no assigned account. '
      'Clear the saved library to continue. Clearing removes saved songs, '
      'playlists, downloads, and pending edits.';

  Future<void> initialize() async {
    final scope = _scope;
    final attemptGeneration = scope.generation;
    try {
      final preferences = await SharedPreferences.getInstance();
      if (scope.generation != attemptGeneration) return;
      final smallStreaming = preferences.getBool('smallStreaming') ?? false;
      final smallDownloads = preferences.getBool('smallDownloads') ?? false;
      final normalization = preferences.getBool('normalization') ?? false;
      final glassEffects = preferences.getBool('glassEffects') ?? true;
      final glassOpacity = preferences.getDouble('glassOpacity') ?? .8;
      JellyfinSession? savedSession;
      try {
        savedSession = await scope.exclusive(
          () => ref.read(sessionStoreProvider).load(),
        );
      } catch (error) {
        if (scope.generation != attemptGeneration) return;
        state = AppState(
          status: AppStatus.signedOut,
          smallStreaming: smallStreaming,
          smallDownloads: smallDownloads,
          normalization: normalization,
          glassEffects: glassEffects,
          glassOpacity: glassOpacity,
          error: sessionRestoreErrorMessage(error),
        );
        return;
      }
      if (scope.generation != attemptGeneration) return;
      if (savedSession == null) {
        if (await _hasCachedAccountData()) {
          if (scope.generation != attemptGeneration) return;
          state = AppState(
            status: AppStatus.signedOut,
            smallStreaming: smallStreaming,
            smallDownloads: smallDownloads,
            normalization: normalization,
            glassEffects: glassEffects,
            glassOpacity: glassOpacity,
            cacheOwnerConflict: true,
            cacheOwnerMessage: _conflictMessageForUnknown(),
          );
          return;
        }
        const developmentLogin = DevelopmentLogin.fromEnvironment();
        if (developmentLogin.canSignIn) {
          state = AppState(
            smallStreaming: smallStreaming,
            smallDownloads: smallDownloads,
            normalization: normalization,
            glassEffects: glassEffects,
            glassOpacity: glassOpacity,
          );
          await signIn(
            developmentLogin.server,
            developmentLogin.username,
            developmentLogin.password,
          );
          return;
        }
        state = AppState(
          status: AppStatus.signedOut,
          smallStreaming: smallStreaming,
          smallDownloads: smallDownloads,
          normalization: normalization,
          glassEffects: glassEffects,
          glassOpacity: glassOpacity,
        );
        return;
      }
      final capturedSaved = savedSession;
      final marker = await scope.exclusive(() => _ownerStore.load());
      if (scope.generation != attemptGeneration) return;
      final sessionKey = accountOwnerKeyForSession(capturedSaved);
      if (marker != null && marker.key != sessionKey) {
        state = AppState(
          status: AppStatus.signedOut,
          smallStreaming: smallStreaming,
          smallDownloads: smallDownloads,
          normalization: normalization,
          glassEffects: glassEffects,
          glassOpacity: glassOpacity,
          cacheOwnerConflict: true,
          cacheOwnerMessage: _conflictMessageForMismatch(),
        );
        return;
      }
      if (marker == null) {
        final empty = await _isCacheEmpty();
        if (scope.generation != attemptGeneration) return;
        if (empty) {
          await scope.exclusive(() => _ownerStore.saveOwner(capturedSaved));
          if (scope.generation != attemptGeneration) return;
        } else {
          // Legacy cache with a valid saved session: migrate ownership from
          // that saved session before refresh/delivery.
          await scope.exclusive(() => _ownerStore.saveOwner(capturedSaved));
          if (scope.generation != attemptGeneration) return;
        }
      }
      final lease = scope.activate(capturedSaved);
      final lastSyncedAt = _readLastSyncedAt(preferences, capturedSaved);
      state = AppState(
        status: AppStatus.ready,
        session: capturedSaved,
        smallStreaming: smallStreaming,
        smallDownloads: smallDownloads,
        normalization: normalization,
        glassEffects: glassEffects,
        glassOpacity: glassOpacity,
        lastSyncedAt: lastSyncedAt,
      );
      unawaited(
        _enqueueLifecycle(
          () => _restoreLocalPlayback(
            lease,
            smallStreaming: smallStreaming,
            normalization: normalization,
          ),
        ),
      );
      unawaited(refresh(silent: true, force: true));
    } catch (error) {
      if (scope.generation != attemptGeneration) return;
      state = state.copyWith(
        status: AppStatus.signedOut,
        syncing: false,
        error: sessionRestoreErrorMessage(error),
      );
    }
  }

  Future<void> _restoreLocalPlayback(
    AccountLease lease, {
    required bool smallStreaming,
    required bool normalization,
  }) async {
    final scope = _scope;
    if (!scope.isCurrent(lease)) return;
    try {
      await ref
          .read(playbackProvider)
          .configure(
            lease.session,
            smallStreaming: smallStreaming,
            normalization: normalization,
          );
      if (!scope.isCurrent(lease)) return;
      try {
        ref.read(castControllerProvider).configure(lease.session);
      } catch (_) {}
      if (!scope.isCurrent(lease)) return;
      ref.read(carControllerProvider.notifier).setSignedIn(true);
      final cached = await ref.read(databaseProvider).allTracks();
      if (!scope.isCurrent(lease)) return;
      if (cached.isEmpty) return;
      await ref.read(playbackProvider).restore(cached);
      if (!scope.isCurrent(lease)) return;
      ref.read(carControllerProvider.notifier).refreshCatalog(tracks: cached);
    } catch (_) {}
  }

  Future<bool> signIn(String server, String username, String password) async {
    final scope = _scope;
    final attemptGeneration = scope.generation;
    state = state.copyWith(
      syncing: true,
      clearError: true,
      clearCacheConflict: true,
    );
    late final JellyfinSession authenticated;
    try {
      final deviceId = await scope.exclusive(
        () => ref.read(sessionStoreProvider).getDeviceId(),
      );
      if (scope.generation != attemptGeneration) return false;
      authenticated = await ref
          .read(jellyfinClientProvider)
          .authenticate(
            serverUrl: server,
            username: username,
            password: password,
            deviceId: deviceId,
          );
    } catch (error) {
      if (scope.generation != attemptGeneration) return false;
      state = state.copyWith(
        status: AppStatus.signedOut,
        syncing: false,
        error: error.toString(),
        clearSession: true,
      );
      return false;
    }
    if (scope.generation != attemptGeneration) return false;
    // Validate ownership and persist the session atomically inside the
    // local-write fence. A queued sign-in cannot revive an account that was
    // invalidated while authentication was in flight.
    AccountLease? newLease;
    var conflict = false;
    String? conflictMessage;
    await scope.exclusive(() async {
      if (scope.generation != attemptGeneration) return;
      final marker = await _ownerStore.load();
      if (scope.generation != attemptGeneration) return;
      final ownerKey = accountOwnerKeyForSession(authenticated);
      if (marker != null && marker.key != ownerKey) {
        conflict = true;
        conflictMessage = _conflictMessageForMismatch();
        return;
      }
      if (marker == null && await _hasCachedAccountData()) {
        // Unknown/legacy cache without a marker: never infer ownership from
        // a newly entered account; require an explicit clear.
        if (scope.generation != attemptGeneration) return;
        conflict = true;
        conflictMessage = _conflictMessageForUnknown();
        return;
      }
      if (scope.generation != attemptGeneration) return;
      await ref.read(sessionStoreProvider).save(authenticated);
      if (scope.generation != attemptGeneration) return;
      if (marker == null) {
        await _ownerStore.saveOwner(authenticated);
        if (scope.generation != attemptGeneration) return;
      }
      newLease = scope.activate(authenticated);
    });
    if (conflict) {
      // Block the switch and keep rows. Publish only when no newer
      // generation won while we were queued; otherwise leave the latest
      // signed-out/ready state alone.
      if (scope.generation != attemptGeneration) return false;
      state = state.copyWith(
        status: AppStatus.signedOut,
        syncing: false,
        clearSession: true,
        cacheOwnerConflict: true,
        cacheOwnerMessage: conflictMessage ?? _conflictMessageForMismatch(),
      );
      return false;
    }
    final lease = newLease;
    if (lease == null) return false;
    if (!scope.isCurrent(lease)) return false;
    _remoteAccountId = null;
    state = state.copyWith(
      status: AppStatus.ready,
      session: authenticated,
      syncing: true,
    );
    await _enqueueLifecycle(() async {
      if (!scope.isCurrent(lease)) return;
      await ref
          .read(playbackProvider)
          .configure(
            lease.session,
            smallStreaming: state.smallStreaming,
            normalization: state.normalization,
          );
      if (!scope.isCurrent(lease)) return;
      try {
        ref.read(castControllerProvider).configure(lease.session);
      } catch (_) {}
      if (!scope.isCurrent(lease)) return;
      ref.read(carControllerProvider.notifier).setSignedIn(true);
    });
    if (!scope.isCurrent(lease)) return false;
    await refresh();
    return scope.isCurrent(lease);
  }

  Future<void> refresh({bool silent = false, bool force = false}) {
    final scope = _scope;
    final lease = _leaseOrActivate();
    if (lease == null) return Future.value();
    final running = _refreshFuture;
    final runningLease = _refreshLease;
    if (running != null &&
        runningLease != null &&
        scope.isCurrent(runningLease) &&
        runningLease.generation == lease.generation &&
        runningLease.ownerKey == lease.ownerKey) {
      return running;
    }
    if (silent &&
        !force &&
        withinRefreshCooldown(state.lastSyncedAt, DateTime.now())) {
      return Future.value();
    }
    _refreshRetryTimer?.cancel();
    final refresh = _refreshForLease(lease, silent: silent);
    _refreshFuture = refresh;
    _refreshLease = lease;
    return refresh.whenComplete(() {
      if (identical(_refreshFuture, refresh)) {
        _refreshFuture = null;
        _refreshLease = null;
      }
    });
  }

  Future<void> _refreshForLease(
    AccountLease lease, {
    required bool silent,
  }) async {
    final scope = _scope;
    if (!scope.isCurrent(lease)) return;
    state = state.copyWith(
      syncing: !silent,
      clearError: true,
      clearSyncError: true,
    );
    try {
      final client = ref.read(jellyfinClientProvider);
      final database = ref.read(databaseProvider);
      final session = await _refreshSessionIdentity(lease, lease.session);
      if (!scope.isCurrent(lease)) return;
      if (session == null) return;
      state = state.copyWith(session: session);
      final flushed = await _flushPending(lease);
      if (!scope.isCurrent(lease)) return;
      if (!flushed) {
        // Pending delivery blocked; still continue with the catalog sync
        // using the current lease.
      }
      Object? playlistError;
      try {
        final playlists = await client.fetchPlaylists(session);
        if (!scope.isCurrent(lease)) return;
        final applied = await scope.commit(
          lease,
          () => database.replacePlaylists(playlists),
        );
        if (applied == AccountWriteResult.stale) return;
      } catch (error) {
        if (!scope.isCurrent(lease)) return;
        playlistError = error;
      }
      final tracks = await client.fetchTracks(session);
      if (!scope.isCurrent(lease)) return;
      final trackApplied = await scope.commit(
        lease,
        () => database.replaceTracks(tracks),
      );
      if (trackApplied == AccountWriteResult.stale) return;
      if (!scope.isCurrent(lease)) return;
      await ref
          .read(downloadProvider)
          .reconcile(tracks.map((track) => track.id.value));
      if (!scope.isCurrent(lease)) return;
      try {
        final albumDates = await client.fetchAlbumDates(session);
        if (!scope.isCurrent(lease)) return;
        await scope.commit(lease, () => database.replaceAlbumDates(albumDates));
        if (!scope.isCurrent(lease)) return;
      } catch (_) {
        if (!scope.isCurrent(lease)) return;
      }
      final catalog = await ref.read(databaseProvider).allTracks();
      if (!scope.isCurrent(lease)) return;
      try {
        await ref.read(carControllerProvider.notifier).refreshNow();
      } catch (_) {}
      if (!scope.isCurrent(lease)) return;
      if (ref.read(playbackProvider).queue.isEmpty) {
        await ref.read(playbackProvider).restore(catalog);
        if (!scope.isCurrent(lease)) return;
      }
      await ref
          .read(downloadProvider)
          .resume(
            session,
            await _tracksByRecency(),
            small: state.smallDownloads,
          );
      if (!scope.isCurrent(lease)) return;
      final accountId = '${session.serverId}:${session.userId}';
      if (_remoteAccountId != accountId) {
        _remoteAccountId = accountId;
        unawaited(ref.read(remoteSessionProvider).configure(session));
      }
      try {
        ref.read(castControllerProvider).configure(session);
      } catch (_) {}
      if (!scope.isCurrent(lease)) return;
      final syncedAt = DateTime.now();
      _refreshRetryAttempt = 0;
      final preferences = await SharedPreferences.getInstance();
      if (!scope.isCurrent(lease)) return;
      await preferences.setString(
        _lastSyncedKey(session),
        syncedAt.toIso8601String(),
      );
      if (!scope.isCurrent(lease)) return;
      state = state.copyWith(
        syncing: false,
        clearError: true,
        syncError: playlistError == null
            ? null
            : 'Songs updated, but saved playlists could not be refreshed.',
        clearSyncError: playlistError == null,
        lastSyncedAt: syncedAt,
      );
    } catch (error) {
      if (!ref.mounted) return;
      if (error is JellyfinException && error.statusCode == 401) {
        if (scope.isCurrent(lease)) await _expireSession();
        return;
      }
      if (!scope.isCurrent(lease)) return;
      _scheduleRefreshRetry(lease);
      if (!ref.mounted) return;
      state = silent
          ? state.copyWith(
              syncing: false,
              clearError: true,
              syncError: 'Could not reach Jellyfin. Using your saved library.',
            )
          : state.copyWith(
              syncing: false,
              error: error.toString(),
              syncError: 'Could not reach Jellyfin. Using your saved library.',
            );
    }
  }

  Future<List<Track>> _tracksByRecency() =>
      ref.read(databaseProvider).allTracksByDateAdded();

  /// Refreshes only the Recently Played cache without a full library sync.
  Future<void> refreshHistory({int limit = 100}) async {
    final scope = _scope;
    final lease = _leaseOrActivate();
    if (lease == null) return;
    final session = lease.session;
    late final List<TracksCompanion> rows;
    try {
      rows = await ref
          .read(jellyfinClientProvider)
          .fetchRecentlyPlayed(session, limit: limit);
    } catch (_) {
      return;
    }
    if (!scope.isCurrent(lease)) return;
    if (rows.isEmpty) return;
    await scope.commit(
      lease,
      () => ref.read(databaseProvider).upsertTracks(rows),
    );
  }

  DateTime? _readLastSyncedAt(
    SharedPreferences preferences,
    JellyfinSession session,
  ) => DateTime.tryParse(preferences.getString(_lastSyncedKey(session)) ?? '');

  String _lastSyncedKey(JellyfinSession session) =>
      'lastSyncedAt.${session.serverId}.${session.userId}';

  void _scheduleRefreshRetry(AccountLease lease) {
    if (!ref.mounted) return;
    final scope = _scope;
    if (!scope.isCurrent(lease)) return;
    if (_refreshRetryTimer?.isActive == true) return;
    final exponent = _refreshRetryAttempt.clamp(0, 4);
    final delay = Duration(seconds: 15 * (1 << exponent));
    _refreshRetryAttempt++;
    _refreshRetryTimer = Timer(delay, () {
      if (!scope.isCurrent(lease)) return;
      unawaited(refresh(silent: true, force: true));
    });
  }

  Future<void> toggleFavorite(String trackId, bool favorite) async {
    final scope = _scope;
    final lease = _leaseOrActivate();
    if (lease == null) return;
    final applied = await scope.commit(
      lease,
      () => ref.read(databaseProvider).saveFavoriteEdit(trackId, favorite),
    );
    if (applied == AccountWriteResult.stale) return;
    if (!scope.isCurrent(lease)) return;
    await _flushPending(lease);
  }

  Future<void> deleteTrack(String trackId) async {
    final scope = _scope;
    final lease = _leaseOrActivate();
    if (lease == null) {
      throw const JellyfinException('Sign in before deleting a song.');
    }
    final session = lease.session;
    await ref.read(jellyfinClientProvider).deleteItem(session, trackId);
    if (!scope.isCurrent(lease)) return;
    await scope.commit(lease, () => _removeLocalTrack(trackId));
  }

  Future<void> deleteAlbum(Iterable<String> trackIds) async {
    final scope = _scope;
    final lease = _leaseOrActivate();
    if (lease == null) return;
    final session = lease.session;
    for (final trackId in trackIds) {
      if (!scope.isCurrent(lease)) return;
      await ref.read(jellyfinClientProvider).deleteItem(session, trackId);
      if (!scope.isCurrent(lease)) return;
      final applied = await scope.commit(
        lease,
        () => _removeLocalTrack(trackId),
      );
      if (applied == AccountWriteResult.stale) return;
    }
  }

  Future<void> _removeLocalTrack(String trackId) async {
    try {
      await ref.read(downloadProvider).remove(trackId);
    } catch (_) {}
    await ref.read(databaseProvider).removeTrack(trackId);
    try {
      await ref.read(playbackProvider).removeTrack(trackId);
    } catch (_) {}
  }

  Future<void> addToPlaylist(String playlistId, String trackId) async {
    final scope = _scope;
    final lease = _leaseOrActivate();
    if (lease == null) return;
    final applied = await scope.commit(
      lease,
      () =>
          ref.read(databaseProvider).savePlaylistAddition(playlistId, trackId),
    );
    if (applied == AccountWriteResult.stale) return;
    if (!scope.isCurrent(lease)) return;
    await _flushPending(lease);
  }

  Future<void> createPlaylist(String name, List<String> trackIds) async {
    final scope = _scope;
    final lease = _leaseOrActivate();
    if (lease == null || name.trim().isEmpty) return;
    final session = lease.session;
    try {
      await ref
          .read(jellyfinClientProvider)
          .createPlaylist(session, name.trim(), trackIds);
      if (!scope.isCurrent(lease)) return;
      final playlists = await ref
          .read(jellyfinClientProvider)
          .fetchPlaylists(session);
      if (!scope.isCurrent(lease)) return;
      await scope.commit(
        lease,
        () => ref.read(databaseProvider).replacePlaylists(playlists),
      );
    } catch (error) {
      if (!scope.isCurrent(lease)) return;
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> renamePlaylist(String playlistId, String name) async {
    final scope = _scope;
    final lease = _leaseOrActivate();
    if (lease == null || name.trim().isEmpty) return;
    final session = lease.session;
    try {
      await ref
          .read(jellyfinClientProvider)
          .renamePlaylist(session, playlistId, name.trim());
      if (!scope.isCurrent(lease)) return;
      final playlists = await ref
          .read(jellyfinClientProvider)
          .fetchPlaylists(session);
      if (!scope.isCurrent(lease)) return;
      await scope.commit(
        lease,
        () => ref.read(databaseProvider).replacePlaylists(playlists),
      );
    } catch (error) {
      if (!scope.isCurrent(lease)) return;
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> deletePlaylist(String playlistId) async {
    final scope = _scope;
    final lease = _leaseOrActivate();
    if (lease == null) {
      throw const JellyfinException('Sign in before deleting a playlist.');
    }
    final session = lease.session;
    await ref.read(jellyfinClientProvider).deleteItem(session, playlistId);
    if (!scope.isCurrent(lease)) return;
    await scope.commit(
      lease,
      () => ref.read(databaseProvider).removePlaylist(playlistId),
    );
  }

  Future<void> signOut() async {
    final scope = _scope;
    // Invalidate synchronously before any awaited cleanup so late work
    // observes the new generation immediately.
    scope.invalidate();
    _refreshRetryTimer?.cancel();
    _refreshRetryTimer = null;
    _refreshRetryAttempt = 0;
    _refreshLease = null;
    _refreshFuture = null;
    _remoteAccountId = null;
    state = state.copyWith(
      status: AppStatus.signedOut,
      clearSession: true,
      syncing: false,
      clearError: true,
      clearCacheConflict: true,
    );
    await _enqueueLifecycle(() async {
      await ref.read(remoteSessionProvider).clear();
      try {
        ref.read(castControllerProvider).configure(null);
      } catch (_) {}
      try {
        await ref.read(castControllerProvider).disconnect(resumeLocal: false);
      } catch (_) {}
      try {
        await ref.read(playbackProvider).clear();
      } catch (_) {}
      try {
        await ref.read(downloadProvider).clear();
      } catch (_) {}
      try {
        ref.read(carControllerProvider.notifier).setSignedIn(false);
      } catch (_) {}
    });
    // Local persistence runs on the serialized fence after already-started
    // writes. The owner marker is cleared only after account data is gone;
    // failures retain the marker (fail closed).
    try {
      await scope.exclusive(() async {
        await ref.read(databaseProvider).clearAccountData();
      });
    } catch (_) {
      return;
    }
    try {
      await scope.exclusive(() => _ownerStore.clear());
    } catch (_) {
      return;
    }
    try {
      await scope.exclusive(() => ref.read(sessionStoreProvider).clear());
    } catch (_) {}
  }

  /// Clears a conflicting saved library after explicit user confirmation.
  ///
  /// Never signs in automatically and never retains a password; the caller
  /// keeps the login form state.
  Future<void> clearSavedLibrary() async {
    final scope = _scope;
    state = state.copyWith(syncing: true, clearError: true);
    await _enqueueLifecycle(() async {
      try {
        await ref.read(remoteSessionProvider).clear();
      } catch (_) {}
      try {
        ref.read(castControllerProvider).configure(null);
      } catch (_) {}
      try {
        await ref.read(castControllerProvider).disconnect(resumeLocal: false);
      } catch (_) {}
      try {
        await ref.read(playbackProvider).clear();
      } catch (_) {}
      try {
        await ref.read(downloadProvider).clear();
      } catch (_) {}
      try {
        ref.read(carControllerProvider.notifier).setSignedIn(false);
      } catch (_) {}
    });
    try {
      await scope.exclusive(() async {
        await ref.read(databaseProvider).clearAccountData();
      });
    } catch (error) {
      state = state.copyWith(syncing: false, error: error.toString());
      return;
    }
    try {
      await scope.exclusive(() => _ownerStore.clear());
    } catch (error) {
      state = state.copyWith(syncing: false, error: error.toString());
      return;
    }
    try {
      await scope.exclusive(() => ref.read(sessionStoreProvider).clear());
    } catch (_) {}
    scope.invalidate();
    _refreshRetryTimer?.cancel();
    _refreshRetryTimer = null;
    _refreshRetryAttempt = 0;
    _refreshLease = null;
    _refreshFuture = null;
    _remoteAccountId = null;
    state = state.copyWith(
      status: AppStatus.signedOut,
      clearSession: true,
      syncing: false,
      clearError: true,
      clearCacheConflict: true,
    );
  }

  void clearError() => state = state.copyWith(clearError: true);

  void clearCacheConflict() => state = state.copyWith(clearCacheConflict: true);

  /// Refreshes session identity and persists it only while [lease] is current.
  ///
  /// Returns null when [lease] went stale or when the refreshed identity
  /// names a different owner (the caller handles the conflict without
  /// saving or swapping the lease).
  Future<JellyfinSession?> _refreshSessionIdentity(
    AccountLease lease,
    JellyfinSession session,
  ) async {
    final scope = _scope;
    late final JellyfinSession refreshed;
    try {
      refreshed = await ref
          .read(jellyfinClientProvider)
          .refreshSession(session);
    } on JellyfinException catch (error) {
      if (error.statusCode == 401) rethrow;
      return session;
    } catch (_) {
      return session;
    }
    if (!scope.isCurrent(lease)) return null;
    if (accountOwnerKeyForSession(refreshed) != lease.ownerKey) {
      await _handleRefreshOwnerChange(lease, refreshed);
      return null;
    }
    final applied = await scope.commit(
      lease,
      () => ref.read(sessionStoreProvider).save(refreshed),
    );
    if (applied == AccountWriteResult.stale) return null;
    if (!scope.isCurrent(lease)) return null;
    try {
      final updated = scope.updateSession(lease, refreshed);
      return updated.session;
    } on StateError {
      return null;
    }
  }

  Future<void> _handleRefreshOwnerChange(
    AccountLease lease,
    JellyfinSession refreshed,
  ) async {
    final scope = _scope;
    final marker = await scope.exclusive(() => _ownerStore.load());
    if (!scope.isCurrent(lease)) return;
    final refreshedKey = accountOwnerKeyForSession(refreshed);
    if (marker != null && marker.key == refreshedKey) {
      // Marker already names the refreshed account (e.g. migrated
      // elsewhere); still refuse a silent lease swap and require the
      // explicit flow. Fall through to conflict.
    }
    scope.invalidate();
    _refreshRetryTimer?.cancel();
    _refreshRetryTimer = null;
    _refreshLease = null;
    _refreshFuture = null;
    _remoteAccountId = null;
    state = state.copyWith(
      status: AppStatus.signedOut,
      clearSession: true,
      syncing: false,
      cacheOwnerConflict: true,
      cacheOwnerMessage: _conflictMessageForMismatch(),
    );
    await _enqueueLifecycle(() async {
      try {
        await ref.read(remoteSessionProvider).clear();
      } catch (_) {}
      try {
        ref.read(castControllerProvider).configure(null);
      } catch (_) {}
      try {
        await ref.read(downloadProvider).suspend();
      } catch (_) {}
      try {
        await ref.read(playbackProvider).clear();
      } catch (_) {}
      try {
        ref.read(carControllerProvider.notifier).setSignedIn(false);
      } catch (_) {}
    });
  }

  Future<void> _expireSession() async {
    final scope = _scope;
    // Invalidate synchronously; retain cache rows and the owner marker.
    scope.invalidate();
    _refreshRetryTimer?.cancel();
    _refreshRetryTimer = null;
    _refreshRetryAttempt = 0;
    _refreshLease = null;
    _refreshFuture = null;
    _remoteAccountId = null;
    state = state.copyWith(
      status: AppStatus.signedOut,
      clearSession: true,
      syncing: false,
      error: 'Your Jellyfin session is no longer valid. Sign in again.',
    );
    await _enqueueLifecycle(() async {
      try {
        await ref.read(downloadProvider).suspend();
      } catch (_) {}
      try {
        await ref.read(remoteSessionProvider).clear();
      } catch (_) {}
      try {
        ref.read(castControllerProvider).configure(null);
      } catch (_) {}
      try {
        await ref.read(castControllerProvider).disconnect(resumeLocal: false);
      } catch (_) {}
      try {
        await ref.read(playbackProvider).clear();
      } catch (_) {}
      try {
        ref.read(carControllerProvider.notifier).setSignedIn(false);
      } catch (_) {}
    });
    try {
      await scope.exclusive(() => ref.read(sessionStoreProvider).clear());
    } catch (_) {}
  }

  Future<void> setSmallStreaming(bool value) async {
    final scope = _scope;
    final lease = _leaseOrActivate();
    state = state.copyWith(smallStreaming: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('smallStreaming', value);
    if (lease == null || !scope.isCurrent(lease)) return;
    await ref
        .read(playbackProvider)
        .configure(
          lease.session,
          smallStreaming: value,
          normalization: state.normalization,
        );
  }

  Future<void> setSmallDownloads(bool value) async {
    state = state.copyWith(smallDownloads: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('smallDownloads', value);
  }

  Future<void> setNormalization(bool value) async {
    final scope = _scope;
    final lease = _leaseOrActivate();
    state = state.copyWith(normalization: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('normalization', value);
    if (lease == null || !scope.isCurrent(lease)) return;
    await ref
        .read(playbackProvider)
        .configure(
          lease.session,
          smallStreaming: state.smallStreaming,
          normalization: value,
        );
  }

  Future<bool> _flushPending(AccountLease lease) async {
    final scope = _scope;
    if (!scope.isCurrent(lease)) return false;
    final database = ref.read(databaseProvider);
    final client = ref.read(jellyfinClientProvider);
    final operations = await database.pendingOperations();
    for (final operation in operations) {
      if (!scope.isCurrent(lease)) return false;
      try {
        final payload = jsonDecode(operation.payload) as Map<String, dynamic>;
        if (operation.kind == 'favorite') {
          await client.setFavorite(
            lease.session,
            operation.targetId,
            payload['favorite'] as bool,
          );
        } else if (operation.kind == 'playlistAdd') {
          await client.addToPlaylist(lease.session, operation.targetId, [
            payload['trackId'] as String,
          ]);
        } else {
          await scope.commit(
            lease,
            () => database.incrementPendingAttempts(operation.id),
          );
          return false;
        }
        if (!scope.isCurrent(lease)) return false;
        final acknowledged = await scope.commit(
          lease,
          () => database.completePending(operation.id),
        );
        if (acknowledged == AccountWriteResult.stale) return false;
      } catch (_) {
        if (!scope.isCurrent(lease)) return false;
        try {
          await scope.commit(
            lease,
            () => database.incrementPendingAttempts(operation.id),
          );
        } catch (_) {}
        return false;
      }
    }
    return scope.isCurrent(lease);
  }

  Future<void> setGlassEffects(bool value) async {
    state = state.copyWith(glassEffects: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('glassEffects', value);
  }

  Future<void> setGlassOpacity(double value) async {
    state = state.copyWith(glassOpacity: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble('glassOpacity', value);
  }
}
