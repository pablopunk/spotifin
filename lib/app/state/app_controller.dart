import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/jellyfin/jellyfin_client.dart';
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
  );
}

class AppController extends Notifier<AppState> {
  Future<void>? _refreshFuture;
  Timer? _refreshRetryTimer;
  int _refreshRetryAttempt = 0;
  int _sessionGeneration = 0;
  String? _remoteAccountId;

  @override
  AppState build() {
    ref.onDispose(() => _refreshRetryTimer?.cancel());
    return const AppState();
  }

  Future<void> initialize() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final smallStreaming = preferences.getBool('smallStreaming') ?? false;
      final smallDownloads = preferences.getBool('smallDownloads') ?? false;
      final normalization = preferences.getBool('normalization') ?? false;
      final glassEffects = preferences.getBool('glassEffects') ?? true;
      final glassOpacity = preferences.getDouble('glassOpacity') ?? .8;
      final savedSession = await ref.read(sessionStoreProvider).load();
      if (savedSession == null) {
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
      _sessionGeneration++;
      final lastSyncedAt = _readLastSyncedAt(preferences, savedSession);
      state = AppState(
        status: AppStatus.ready,
        session: savedSession,
        smallStreaming: smallStreaming,
        smallDownloads: smallDownloads,
        normalization: normalization,
        glassEffects: glassEffects,
        glassOpacity: glassOpacity,
        lastSyncedAt: lastSyncedAt,
      );
      unawaited(
        _restoreLocalPlayback(
          savedSession,
          smallStreaming: smallStreaming,
          normalization: normalization,
        ),
      );
      unawaited(refresh(silent: true));
    } catch (error) {
      state = state.copyWith(
        status: AppStatus.signedOut,
        syncing: false,
        error: 'Could not open saved Spotifin data: $error',
      );
    }
  }

  Future<void> _restoreLocalPlayback(
    JellyfinSession session, {
    required bool smallStreaming,
    required bool normalization,
  }) async {
    try {
      await ref
          .read(playbackProvider)
          .configure(
            session,
            smallStreaming: smallStreaming,
            normalization: normalization,
          );
      final cached = await ref.read(databaseProvider).allTracks();
      if (cached.isEmpty) return;
      await ref.read(playbackProvider).restore(cached);
      await ref
          .read(carPlayProvider)
          .configure(cached, ref.read(playbackProvider));
    } catch (_) {}
  }

  Future<bool> signIn(String server, String username, String password) async {
    state = state.copyWith(syncing: true, clearError: true);
    try {
      final session = await ref
          .read(jellyfinClientProvider)
          .authenticate(
            serverUrl: server,
            username: username,
            password: password,
            deviceId: await ref.read(sessionStoreProvider).getDeviceId(),
          );
      await ref.read(sessionStoreProvider).save(session);
      await ref
          .read(playbackProvider)
          .configure(
            session,
            smallStreaming: state.smallStreaming,
            normalization: state.normalization,
          );
      _sessionGeneration++;
      _remoteAccountId = null;
      state = state.copyWith(
        status: AppStatus.ready,
        session: session,
        syncing: true,
      );
      await refresh();
      return true;
    } catch (error) {
      state = state.copyWith(
        status: AppStatus.signedOut,
        syncing: false,
        error: error.toString(),
        clearSession: true,
      );
      return false;
    }
  }

  Future<void> refresh({bool silent = false}) {
    final running = _refreshFuture;
    if (running != null) return running;
    _refreshRetryTimer?.cancel();
    final refresh = _refresh(silent: silent);
    _refreshFuture = refresh;
    return refresh.whenComplete(() {
      if (identical(_refreshFuture, refresh)) _refreshFuture = null;
    });
  }

  Future<void> _refresh({required bool silent}) async {
    final savedSession = state.session;
    if (savedSession == null) return;
    final generation = _sessionGeneration;
    state = state.copyWith(
      syncing: !silent,
      clearError: true,
      clearSyncError: true,
    );
    try {
      final client = ref.read(jellyfinClientProvider);
      final database = ref.read(databaseProvider);
      final session = await _refreshSessionIdentity(savedSession);
      if (generation != _sessionGeneration) return;
      state = state.copyWith(session: session);
      await _flushPending();
      Object? playlistError;
      try {
        final playlists = await client.fetchPlaylists(session);
        if (generation != _sessionGeneration) return;
        await database.replacePlaylists(playlists);
      } catch (error) {
        playlistError = error;
      }
      final tracks = await client.fetchTracks(session);
      if (generation != _sessionGeneration) return;
      await database.replaceTracks(tracks);
      await ref
          .read(downloadProvider)
          .reconcile(tracks.map((track) => track.id.value));
      try {
        final albumDates = await client.fetchAlbumDates(session);
        if (generation != _sessionGeneration) return;
        await database.replaceAlbumDates(albumDates);
      } catch (_) {}
      final catalog = await ref.read(databaseProvider).allTracks();
      await ref
          .read(carPlayProvider)
          .configure(catalog, ref.read(playbackProvider));
      if (ref.read(playbackProvider).queue.isEmpty) {
        await ref.read(playbackProvider).restore(catalog);
      }
      await ref
          .read(downloadProvider)
          .resume(
            session,
            await _tracksByRecency(),
            small: state.smallDownloads,
          );
      final accountId = '${session.serverId}:${session.userId}';
      if (_remoteAccountId != accountId) {
        _remoteAccountId = accountId;
        unawaited(ref.read(remoteSessionProvider).configure(session));
      }
      final syncedAt = DateTime.now();
      _refreshRetryAttempt = 0;
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _lastSyncedKey(session),
        syncedAt.toIso8601String(),
      );
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
      if (error is JellyfinException && error.statusCode == 401) {
        if (generation == _sessionGeneration) await _expireSession();
        return;
      }
      if (generation != _sessionGeneration) return;
      _scheduleRefreshRetry();
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

  DateTime? _readLastSyncedAt(
    SharedPreferences preferences,
    JellyfinSession session,
  ) => DateTime.tryParse(preferences.getString(_lastSyncedKey(session)) ?? '');

  String _lastSyncedKey(JellyfinSession session) =>
      'lastSyncedAt.${session.serverId}.${session.userId}';

  void _scheduleRefreshRetry() {
    if (state.session == null || _refreshRetryTimer?.isActive == true) return;
    final exponent = _refreshRetryAttempt.clamp(0, 4);
    final delay = Duration(seconds: 15 * (1 << exponent));
    _refreshRetryAttempt++;
    _refreshRetryTimer = Timer(delay, () => unawaited(refresh(silent: true)));
  }

  Future<void> toggleFavorite(String trackId, bool favorite) async {
    final session = state.session;
    if (session == null) return;
    await ref.read(databaseProvider).saveFavoriteEdit(trackId, favorite);
    await _flushPending();
  }

  Future<void> deleteTrack(String trackId) async {
    final session = state.session;
    if (session == null) {
      throw const JellyfinException('Sign in before deleting a song.');
    }
    await ref.read(jellyfinClientProvider).deleteItem(session, trackId);
    await _removeLocalTrack(trackId);
  }

  Future<void> deleteAlbum(Iterable<String> trackIds) async {
    for (final trackId in trackIds) {
      await deleteTrack(trackId);
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
    final session = state.session;
    if (session == null) return;
    await ref.read(databaseProvider).savePlaylistAddition(playlistId, trackId);
    if (await _flushPending()) {
      try {
        final playlists = await ref
            .read(jellyfinClientProvider)
            .fetchPlaylists(session);
        await ref.read(databaseProvider).replacePlaylists(playlists);
      } catch (_) {}
    }
  }

  Future<void> createPlaylist(String name, List<String> trackIds) async {
    final session = state.session;
    if (session == null || name.trim().isEmpty) return;
    try {
      await ref
          .read(jellyfinClientProvider)
          .createPlaylist(session, name.trim(), trackIds);
      final playlists = await ref
          .read(jellyfinClientProvider)
          .fetchPlaylists(session);
      await ref.read(databaseProvider).replacePlaylists(playlists);
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> renamePlaylist(String playlistId, String name) async {
    final session = state.session;
    if (session == null || name.trim().isEmpty) return;
    try {
      await ref
          .read(jellyfinClientProvider)
          .renamePlaylist(session, playlistId, name.trim());
      final playlists = await ref
          .read(jellyfinClientProvider)
          .fetchPlaylists(session);
      await ref.read(databaseProvider).replacePlaylists(playlists);
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> signOut() async {
    _refreshRetryTimer?.cancel();
    _refreshRetryAttempt = 0;
    _sessionGeneration++;
    _remoteAccountId = null;
    final session = state.session;
    await ref.read(remoteSessionProvider).clear();
    if (session != null) {
      try {
        await ref.read(jellyfinClientProvider).logout(session);
      } catch (_) {}
    }
    await ref.read(playbackProvider).clear();
    await ref.read(downloadProvider).clear();
    await ref.read(databaseProvider).clearAccountData();
    await ref.read(sessionStoreProvider).clear();
    state = state.copyWith(
      status: AppStatus.signedOut,
      clearSession: true,
      syncing: false,
      clearError: true,
    );
  }

  void clearError() => state = state.copyWith(clearError: true);

  Future<JellyfinSession> _refreshSessionIdentity(
    JellyfinSession session,
  ) async {
    try {
      final refreshed = await ref
          .read(jellyfinClientProvider)
          .refreshSession(session);
      await ref.read(sessionStoreProvider).save(refreshed);
      return refreshed;
    } on JellyfinException catch (error) {
      if (error.statusCode == 401) rethrow;
      return session;
    } catch (_) {
      return session;
    }
  }

  Future<void> _expireSession() async {
    _refreshRetryTimer?.cancel();
    _refreshRetryAttempt = 0;
    _sessionGeneration++;
    _remoteAccountId = null;
    await ref.read(downloadProvider).suspend();
    await ref.read(remoteSessionProvider).clear();
    await ref.read(playbackProvider).clear();
    await ref.read(sessionStoreProvider).clear();
    state = state.copyWith(
      status: AppStatus.signedOut,
      clearSession: true,
      syncing: false,
      error: 'Your Jellyfin session is no longer valid. Sign in again.',
    );
  }

  Future<void> setSmallStreaming(bool value) async {
    state = state.copyWith(smallStreaming: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('smallStreaming', value);
    final session = state.session;
    if (session != null) {
      await ref
          .read(playbackProvider)
          .configure(
            session,
            smallStreaming: value,
            normalization: state.normalization,
          );
    }
  }

  Future<void> setSmallDownloads(bool value) async {
    state = state.copyWith(smallDownloads: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('smallDownloads', value);
  }

  Future<void> setNormalization(bool value) async {
    state = state.copyWith(normalization: value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('normalization', value);
    final session = state.session;
    if (session != null) {
      await ref
          .read(playbackProvider)
          .configure(
            session,
            smallStreaming: state.smallStreaming,
            normalization: value,
          );
    }
  }

  Future<bool> _flushPending() async {
    final session = state.session;
    if (session == null) return false;
    final database = ref.read(databaseProvider);
    final client = ref.read(jellyfinClientProvider);
    final operations = await database.pendingOperations();
    for (final operation in operations) {
      try {
        final payload = jsonDecode(operation.payload) as Map<String, dynamic>;
        if (operation.kind == 'favorite') {
          await client.setFavorite(
            session,
            operation.targetId,
            payload['favorite'] as bool,
          );
        } else if (operation.kind == 'playlistAdd') {
          await client.addToPlaylist(session, operation.targetId, [
            payload['trackId'] as String,
          ]);
        }
        await database.completePending(operation.id);
      } catch (_) {
        await database.incrementPendingAttempts(operation.id);
        return false;
      }
    }
    return true;
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
