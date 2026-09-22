import 'dart:collection';

import '../../storage/database.dart';

/// In-memory play history, most-recent-first.
///
/// The service records the previously playing track every time the current
/// track changes, so history survives queue replacements and restores.
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
