import 'dart:math' as math;

import '../playback/queue_state.dart';
import 'jellyfin_receiver_protocol.dart';

/// Mirror of the list the Jellyfin receiver plays, in the order sent.
///
/// The receiver only knows item ids, so this keeps the occurrence entries
/// behind them. That lets the phone map "the receiver now plays item X" back
/// to one queue occurrence, also when the same track is queued twice.
class ReceiverQueue {
  const ReceiverQueue._(this.entries, this.index);

  /// The slice of [queue] to send with `PlayNow`, starting at its current
  /// entry: a short look-behind for "previous", then the upcoming entries
  /// up to the message size limit.
  factory ReceiverQueue.around(QueueState queue) {
    final loaded = queue.loadedEntries;
    final current = queue.currentIndex ?? 0;
    final start = math.max(0, current - _lookBehind);
    final end = math.min(
      loaded.length,
      start + JellyfinReceiverProtocol.maxItemsPerMessage,
    );
    return ReceiverQueue._(
      List.unmodifiable(loaded.sublist(start, end)),
      current - start,
    );
  }

  static const _lookBehind = 20;

  final List<QueueEntry> entries;
  final int index;

  List<String> get itemIds => [for (final entry in entries) entry.track.id];

  QueueEntry? get current =>
      index >= 0 && index < entries.length ? entries[index] : null;

  QueueEntry? get next =>
      index + 1 < entries.length ? entries[index + 1] : null;

  List<QueueEntry> get upcoming => entries.sublist(index.clamp(0, entries.length));

  ReceiverQueue at(int index) => ReceiverQueue._(entries, index);

  ReceiverQueue appended(List<QueueEntry> more) =>
      ReceiverQueue._(List.unmodifiable([...entries, ...more]), index);

  /// Index of the occurrence the receiver reports as [itemId]. Searches
  /// forward from the current entry first (natural advance), then wraps
  /// (repeat all), so duplicates resolve to the occurrence the receiver
  /// actually reached.
  int? locate(String itemId) {
    if (current?.track.id == itemId) return index;
    for (var i = index + 1; i < entries.length; i++) {
      if (entries[i].track.id == itemId) return i;
    }
    for (var i = 0; i < index && i < entries.length; i++) {
      if (entries[i].track.id == itemId) return i;
    }
    return null;
  }

  /// Entries the receiver lacks for it to play [queue]'s upcoming order, or
  /// null when its upcoming order already differs and needs a reload.
  List<QueueEntry>? missingTail(QueueState queue) {
    final want = _upcomingOf(queue);
    final have = upcoming;
    if (have.length > want.length) return null;
    for (var i = 0; i < have.length; i++) {
      if (have[i].id != want[i].id) return null;
    }
    return want.sublist(have.length);
  }

  static List<QueueEntry> _upcomingOf(QueueState queue) {
    final loaded = queue.loadedEntries;
    final current = queue.currentIndex;
    if (current == null || current < 0 || current >= loaded.length) {
      return const [];
    }
    return loaded.sublist(current);
  }
}
