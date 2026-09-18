import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
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
  static const catalogTimeout = Duration(seconds: 10);

  @override
  CarState build() => const CarState(signedIn: false);

  void setSignedIn(bool value) {
    if (state.signedIn == value) return;
    state = state.copyWith(signedIn: value);
  }

  void refreshCatalog({List<Track>? tracks, List<Playlist>? playlists}) {
    state = state.copyWith(
      tracks: tracks ?? state.tracks,
      playlists: playlists ?? state.playlists,
    );
  }

  Future<void> refreshNow() async {
    final database = ref.read(databaseProvider);
    final tracks = await database.allTracks().timeout(catalogTimeout);
    final playlists = await database.watchPlaylists().first.timeout(
      catalogTimeout,
    );
    state = state.copyWith(tracks: tracks, playlists: playlists);
  }

  Future<void> playTrack(Track track, List<Track> context) =>
      ref.read(playbackProvider).playTrack(track, context);

  Future<void> playTracks(
    List<Track> tracks, {
    int startIndex = 0,
    bool shuffle = false,
  }) => ref
      .read(playbackProvider)
      .replaceQueue(tracks, startIndex: startIndex, shuffle: shuffle);
}
