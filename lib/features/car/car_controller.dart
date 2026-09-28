import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../services/jellyfin/account_scope.dart';
import '../../storage/database.dart';

class CarState {
  const CarState({
    required this.signedIn,
    this.tracks = const [],
    this.playlists = const [],
  });

  final bool signedIn;
  final List<Track> tracks;
  final List<Playlist> playlists;

  bool get isEmpty => tracks.isEmpty;

  CarState copyWith({
    bool? signedIn,
    List<Track>? tracks,
    List<Playlist>? playlists,
  }) => CarState(
    signedIn: signedIn ?? this.signedIn,
    tracks: tracks ?? this.tracks,
    playlists: playlists ?? this.playlists,
  );
}

class CarController extends Notifier<CarState> {
  StreamSubscription<List<Track>>? _tracksSub;
  StreamSubscription<List<Playlist>>? _playlistsSub;
  AccountLease? _subscribed;

  /// Last committed catalog, mirrored so `build` can preserve it across
  /// same-account rebuilds without reading notifier state during build.
  CarState _lastCommitted = const CarState(signedIn: false);

  @override
  CarState build() {
    final scope = ref.watch(accountScopeProvider);
    // The scope object is stable; its internal notifications need an
    // explicit listener to rebuild on activation/invalidation.
    scope.removeListener(_resubscribe);
    scope.addListener(_resubscribe);
    ref.onDispose(() => scope.removeListener(_resubscribe));
    final lease = scope.current;
    if (lease == null) {
      // Account invalidation publishes the signed-out empty state
      // immediately, before any held old event can publish.
      _cancelSubscriptions();
      _subscribed = null;
      _lastCommitted = const CarState(signedIn: false);
      return _lastCommitted;
    }
    final subscribed = _subscribed;
    if (subscribed == null ||
        subscribed.generation != lease.generation ||
        subscribed.ownerKey != lease.ownerKey) {
      // Newly activated account: drop the old catalog, cancel old
      // subscriptions, then subscribe fresh.
      _cancelSubscriptions();
      _subscribed = lease;
      _tracksSub = ref
          .watch(allTracksStreamProvider)
          .listen(
            (tracks) {
              if (!scope.isCurrent(lease)) return;
              state = state.copyWith(signedIn: true, tracks: tracks);
              _lastCommitted = state;
            },
            onError: (_) {
              // Keep the last committed catalog on stream errors.
            },
          );
      _playlistsSub = ref
          .watch(playlistsStreamProvider)
          .listen(
            (playlists) {
              if (!scope.isCurrent(lease)) return;
              state = state.copyWith(signedIn: true, playlists: playlists);
              _lastCommitted = state;
            },
            onError: (_) {
              // Keep the last committed catalog on stream errors.
            },
          );
      ref.onDispose(_cancelSubscriptions);
      _lastCommitted = const CarState(signedIn: true);
      return _lastCommitted;
    }
    // Same account (identity refresh, provider rebuild): preserve the
    // last committed catalog and only confirm sign-in.
    _subscribed = lease;
    _lastCommitted = _lastCommitted.copyWith(signedIn: true);
    return _lastCommitted;
  }

  void _cancelSubscriptions() {
    _tracksSub?.cancel();
    _tracksSub = null;
    _playlistsSub?.cancel();
    _playlistsSub = null;
  }

  void _resubscribe() {
    ref.invalidateSelf();
  }

  Future<void> playTrack(Track track, List<Track> context) =>
      ref.read(activePlaybackProvider).playTrack(track, context);

  Future<void> playTracks(
    List<Track> tracks, {
    int startIndex = 0,
    bool shuffle = false,
  }) => ref
      .read(activePlaybackProvider)
      .replaceQueue(tracks, startIndex: startIndex, shuffle: shuffle);
}
