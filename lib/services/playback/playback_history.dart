import 'dart:collection';

import '../../storage/database.dart';

/// Transient session overlay for Jellyfin Recently Played history.
///
/// Jellyfin is the durable source of truth (see
/// `JellyfinClient.fetchRecentlyPlayed` and `AppDatabase.watchRecentlyPlayed`):
/// the server records every playback the app reports and the library sync
/// caches `UserData.LastPlayedDate` locally. This class holds *only* the
/// tracks played in the current session since the last server confirmation,
/// most-recent-first, so the History UI can show a just-finished track
/// instantly. It is in-memory, capped, never persisted, and merged on top of
/// the server list with [mergeRecentlyPlayed] (session copy wins, deduped by
/// id). There is intentionally no "clear server history" operation: Jellyfin
/// exposes no such endpoint, so History is not locally clearable.
class PlaybackHistory {
  PlaybackHistory({this.limit = 100});

  final int limit;
  final List<Track> _items = [];

  List<Track> get items => UnmodifiableListView(_items);

  bool get isEmpty => _items.isEmpty;

  void record(Track track) {
    _items.insert(0, track);
    if (_items.length > limit) {
      _items.removeRange(limit, _items.length);
    }
  }

  void clear() => _items.clear();

  void removeTrack(String trackId) =>
      _items.removeWhere((track) => track.id == trackId);

  List<String> toIds() => [for (final track in _items) track.id];

  void load(List<Track> tracks) {
    _items
      ..clear()
      ..addAll(tracks.take(limit));
  }
}
