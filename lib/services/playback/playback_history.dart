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

  /// Most recently played track, or null when history is empty.
  Track? get mostRecent => isEmpty ? null : _items.first;

  /// Removes and returns the most recently played track.
  ///
  /// Returns null when history is empty. Used by Back/Previous navigation so
  /// returning to a played track does not leave it duplicated in history.
  Track? takeFirst() => isEmpty ? null : _items.removeAt(0);

  bool containsId(String id) => _items.any((track) => track.id == id);

  /// Removes history entries down to and including the first occurrence of
  /// [id] (most-recent-first). No-op when [id] is absent.
  ///
  /// Used when playback jumps back to a track that is already in history:
  /// that track becomes current again, and every entry up to it stops being
  /// history because those tracks are current or upcoming now.
  void removeUpToId(String id) {
    final index = _items.indexWhere((track) => track.id == id);
    if (index >= 0) _items.removeRange(0, index + 1);
  }

  /// Removes history entries through [index] (inclusive, most-recent-first).
  ///
  /// Used when playing a history entry directly: entries up to the tapped
  /// one become current/upcoming and must not linger as history.
  void removeThrough(int index) {
    if (index < 0 || _items.isEmpty) return;
    final end = (index + 1).clamp(0, _items.length);
    _items.removeRange(0, end);
  }

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
