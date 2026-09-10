import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/jellyfin/session.dart';
import '../providers.dart';

enum AppStatus { starting, signedOut, ready }

class AppState {
  const AppState({
    this.status = AppStatus.starting,
    this.session,
    this.syncing = false,
    this.error,
  });

  final AppStatus status;
  final JellyfinSession? session;
  final bool syncing;
  final String? error;

  AppState copyWith({
    AppStatus? status,
    JellyfinSession? session,
    bool? syncing,
    String? error,
    bool clearError = false,
    bool clearSession = false,
  }) => AppState(
    status: status ?? this.status,
    session: clearSession ? null : session ?? this.session,
    syncing: syncing ?? this.syncing,
    error: clearError ? null : error ?? this.error,
  );
}

class AppController extends Notifier<AppState> {
  @override
  AppState build() => const AppState();

  Future<void> initialize() async {
    final session = await ref.read(sessionStoreProvider).load();
    if (session == null) {
      state = const AppState(status: AppStatus.signedOut);
      return;
    }
    state = AppState(status: AppStatus.ready, session: session);
    await ref.read(playbackProvider).configure(session);
    final cached = await ref.read(databaseProvider).allTracks();
    if (cached.isNotEmpty) await ref.read(playbackProvider).restore(cached);
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
      await ref.read(playbackProvider).configure(session);
      state = AppState(
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
      final tracks = await client.fetchTracks(session);
      await ref.read(databaseProvider).replaceTracks(tracks);
      final playlists = await client.fetchPlaylists(session);
      await ref.read(databaseProvider).replacePlaylists(playlists);
      final catalog = await ref.read(databaseProvider).allTracks();
      if (ref.read(playbackProvider).queue.isEmpty) {
        await ref.read(playbackProvider).restore(catalog);
      }
      state = state.copyWith(syncing: false, clearError: true);
    } catch (error) {
      state = state.copyWith(syncing: false, error: error.toString());
    }
  }

  Future<void> toggleFavorite(String trackId, bool favorite) async {
    final session = state.session;
    if (session == null) return;
    await ref.read(databaseProvider).setFavorite(trackId, favorite);
    try {
      await ref
          .read(jellyfinClientProvider)
          .setFavorite(session, trackId, favorite);
    } catch (error) {
      await ref.read(databaseProvider).setFavorite(trackId, !favorite);
      state = state.copyWith(error: error.toString());
    }
  }

  Future<void> signOut() async {
    await ref.read(playbackProvider).clear();
    await ref.read(databaseProvider).clearAccountData();
    await ref.read(sessionStoreProvider).clear();
    state = const AppState(status: AppStatus.signedOut);
  }

  void clearError() => state = state.copyWith(clearError: true);
}
