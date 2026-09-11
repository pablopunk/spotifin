import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    this.smallStreaming = false,
    this.smallDownloads = false,
    this.normalization = false,
    this.glassEffects = true,
  });

  final AppStatus status;
  final JellyfinSession? session;
  final bool syncing;
  final String? error;
  final bool smallStreaming;
  final bool smallDownloads;
  final bool normalization;
  final bool glassEffects;

  AppState copyWith({
    AppStatus? status,
    JellyfinSession? session,
    bool? syncing,
    String? error,
    bool clearError = false,
    bool clearSession = false,
    bool? smallStreaming,
    bool? smallDownloads,
    bool? normalization,
    bool? glassEffects,
  }) => AppState(
    status: status ?? this.status,
    session: clearSession ? null : session ?? this.session,
    syncing: syncing ?? this.syncing,
    error: clearError ? null : error ?? this.error,
    smallStreaming: smallStreaming ?? this.smallStreaming,
    smallDownloads: smallDownloads ?? this.smallDownloads,
    normalization: normalization ?? this.normalization,
    glassEffects: glassEffects ?? this.glassEffects,
  );
}

class AppController extends Notifier<AppState> {
  @override
  AppState build() => const AppState();

  Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    final smallStreaming = preferences.getBool('smallStreaming') ?? false;
    final smallDownloads = preferences.getBool('smallDownloads') ?? false;
    final normalization = preferences.getBool('normalization') ?? false;
    final glassEffects = preferences.getBool('glassEffects') ?? true;
    const developmentLogin = DevelopmentLogin.fromEnvironment();
    if (developmentLogin.canSignIn) {
      state = AppState(
        smallStreaming: smallStreaming,
        smallDownloads: smallDownloads,
        normalization: normalization,
        glassEffects: glassEffects,
      );
      await signIn(
        developmentLogin.server,
        developmentLogin.username,
        developmentLogin.password,
      );
      return;
    }
    final session = await ref.read(sessionStoreProvider).load();
    if (session == null) {
      state = AppState(
        status: AppStatus.signedOut,
        smallStreaming: smallStreaming,
        smallDownloads: smallDownloads,
        normalization: normalization,
        glassEffects: glassEffects,
      );
      return;
    }
    state = AppState(
      session: session,
      smallStreaming: smallStreaming,
      smallDownloads: smallDownloads,
      normalization: normalization,
      glassEffects: glassEffects,
    );
    await ref
        .read(playbackProvider)
        .configure(
          session,
          smallStreaming: smallStreaming,
          normalization: normalization,
        );
    final cached = await ref.read(databaseProvider).allTracks();
    if (cached.isNotEmpty) await ref.read(playbackProvider).restore(cached);
    state = state.copyWith(status: AppStatus.ready);
    await refresh(silent: cached.isNotEmpty);
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
          );
      await ref.read(sessionStoreProvider).save(session);
      await ref
          .read(playbackProvider)
          .configure(
            session,
            smallStreaming: state.smallStreaming,
            normalization: state.normalization,
          );
      state = state.copyWith(
        status: AppStatus.ready,
        session: session,
        syncing: true,
      );
      await refresh();
      return true;
    } catch (error) {
      state = AppState(status: AppStatus.signedOut, error: error.toString());
      return false;
    }
  }

  Future<void> refresh({bool silent = false}) async {
    final session = state.session;
    if (session == null || state.syncing && silent) return;
    state = state.copyWith(syncing: !silent, clearError: true);
    try {
      final client = ref.read(jellyfinClientProvider);
      final database = ref.read(databaseProvider);
      await _flushPending();
      var firstPage = true;
      final bufferedTracks = <TracksCompanion>[];
      final tracks = await client.fetchTracks(
        session,
        onPage: (page) async {
          if (firstPage) {
            firstPage = false;
            await database.upsertTracks(page);
            return;
          }
          bufferedTracks.addAll(page);
          if (bufferedTracks.length >= 2000) {
            await database.upsertTracks(bufferedTracks);
            bufferedTracks.clear();
          }
        },
      );
      if (bufferedTracks.isNotEmpty) {
        await database.upsertTracks(bufferedTracks);
      }
      await database.removeTracksExcept(
        tracks.map((track) => track.id.value).toList(growable: false),
      );
      final playlists = await client.fetchPlaylists(session);
      await ref.read(databaseProvider).replacePlaylists(playlists);
      final catalog = await ref.read(databaseProvider).allTracks();
      await ref
          .read(carPlayProvider)
          .configure(catalog, ref.read(playbackProvider));
      if (ref.read(playbackProvider).queue.isEmpty) {
        await ref.read(playbackProvider).restore(catalog);
      }
      state = state.copyWith(syncing: false, clearError: true);
    } catch (error) {
      state = silent
          ? state.copyWith(syncing: false, clearError: true)
          : state.copyWith(syncing: false, error: error.toString());
    }
  }

  Future<void> toggleFavorite(String trackId, bool favorite) async {
    final session = state.session;
    if (session == null) return;
    await ref.read(databaseProvider).saveFavoriteEdit(trackId, favorite);
    await _flushPending();
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
    final session = state.session;
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
}
