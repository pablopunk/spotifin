import 'dart:collection';
import 'dart:math' as math;

import '../../storage/database.dart';
import 'collection_queue.dart';

/// Immutable queue entry identifying one occurrence of a track.
///
/// Two copies of the same track have different [id] values so edits,
/// history, and audio sources can address occurrences rather than track ids.
class QueueEntry {
  const QueueEntry({required this.id, required this.track});

  final String id;
  final Track track;
}

/// Immutable occurrence-based queue state.
///
/// Owns the full collection of entries, the loaded window
/// `[windowStart, windowEnd)`, the nullable **window-relative** current index,
/// and the shuffle flag. Every mutating operation returns a new [QueueState];
/// callers can never write the lists or window offsets in place.
///
/// Manual membership edits ([append], [insertNext], [removeAt], [removeTrack],
/// [reorder]) first discard unloaded collection entries and reset the window
/// start to zero, preserving today's rule that a manual edit stops collection
/// expansion while leaving a valid loaded prefix for later shuffle. Invalid
/// operations return the same state without discarding the tail.
class QueueState {
  const QueueState._(
    this._entries, {
    required this.windowStart,
    required this.windowEnd,
    required this.currentIndex,
    required this.shuffle,
  });

  /// Empty queue: no entries, zero window bounds, null current index.
  factory QueueState.empty() => const QueueState._(
    [],
    windowStart: 0,
    windowEnd: 0,
    currentIndex: null,
    shuffle: false,
  );

  /// Prepares state from a track collection using the current collection
  /// ordering. The initial window holds up to 100 tracks with up to 20
  /// tracks behind the start. Empty input stays empty.
  factory QueueState.prepare(
    List<Track> tracks, {
    int? startIndex,
    required bool shuffle,
    math.Random? random,
    required String Function() newId,
  }) {
    if (tracks.isEmpty) return QueueState.empty();
    final prepared = CollectionQueue.prepare(
      tracks,
      shuffle: shuffle,
      random: random,
      startIndex: startIndex,
    );
    final entries = [
      for (final track in prepared.context)
        QueueEntry(id: newId(), track: track),
    ];
    final start = math.max(0, prepared.index - _queueLookBehind);
    final end = math.min(entries.length, start + _initialQueueSize);
    return QueueState._(
      entries,
      windowStart: start,
      windowEnd: end,
      currentIndex: prepared.index - start,
      shuffle: shuffle,
    );
  }

  /// Restores state from a saved legacy queue: every supplied track is
  /// loaded, the selected index is clamped, and fresh occurrence ids are
  /// allocated. Empty input stays empty.
  factory QueueState.restore(
    List<Track> tracks, {
    required int index,
    required bool shuffle,
    required String Function() newId,
  }) {
    if (tracks.isEmpty) return QueueState.empty();
    final entries = [
      for (final track in tracks) QueueEntry(id: newId(), track: track),
    ];
    return QueueState._(
      entries,
      windowStart: 0,
      windowEnd: entries.length,
      currentIndex: index.clamp(0, entries.length - 1),
      shuffle: shuffle,
    );
  }

  static const _initialQueueSize = 100;
  static const _queueLookBehind = 20;
  static const _queueExtensionSize = 100;

  final List<QueueEntry> _entries;

  final int windowStart;
  final int windowEnd;

  /// Window-relative index of the current entry, or null when unset.
  final int? currentIndex;

  final bool shuffle;

  /// Full collection of entries (loaded plus any unloaded tail).
  List<QueueEntry> get entries => UnmodifiableListView(_entries);

  /// Currently loaded entries: `entries.sublist(windowStart, windowEnd)`.
  List<QueueEntry> get loadedEntries => UnmodifiableListView(
    _entries.sublist(
      windowStart.clamp(0, _entries.length),
      windowEnd.clamp(0, _entries.length),
    ),
  );

  /// Tracks backing the loaded window.
  List<Track> get loadedTracks =>
      UnmodifiableListView([for (final entry in loadedEntries) entry.track]);

  /// Tracks backing the full collection.
  List<Track> get collectionTracks =>
      UnmodifiableListView([for (final entry in _entries) entry.track]);

  /// Currently selected entry, or null when unset or out of range.
  QueueEntry? get currentEntry {
    final index = currentIndex;
    if (index == null) return null;
    final loaded = loadedEntries;
    if (index < 0 || index >= loaded.length) return null;
    return loaded[index];
  }

  /// Loaded tracks from the current entry onward (current first).
  List<Track> get upcomingTracks {
    final loaded = loadedEntries;
    if (loaded.isEmpty) return const [];
    final index = currentIndex;
    if (index == null || index < 0 || index >= loaded.length) {
      return UnmodifiableListView([for (final entry in loaded) entry.track]);
    }
    return UnmodifiableListView([
      for (var i = index; i < loaded.length; i++) loaded[i].track,
    ]);
  }

  /// Whether collection entries beyond the loaded window still exist.
  bool get hasUnloadedTail => windowEnd < _entries.length;

  /// Absolute (collection-relative) index of the current entry, if any.
  int? get absoluteCurrentIndex {
    final index = currentIndex;
    return index == null ? null : windowStart + index;
  }

  /// Appends [track] as a distinct occurrence and stops automatic expansion.
  QueueState append(Track track, {required String Function() newId}) {
    final base = _collapsed();
    final entries = [...base._entries, QueueEntry(id: newId(), track: track)];
    return QueueState._(
      entries,
      windowStart: 0,
      windowEnd: entries.length,
      currentIndex: base.currentIndex,
      shuffle: shuffle,
    );
  }

  /// Inserts [tracks] after the current entry (or at zero when there is no
  /// current entry) as distinct occurrences and stops automatic expansion.
  QueueState insertNext(
    List<Track> tracks, {
    required String Function() newId,
  }) {
    if (tracks.isEmpty) return this;
    final base = _collapsed();
    final insertAt = base.absoluteCurrentIndex == null
        ? 0
        : base.absoluteCurrentIndex! + 1;
    final entries = [
      ...base._entries.sublist(0, insertAt),
      for (final track in tracks) QueueEntry(id: newId(), track: track),
      ...base._entries.sublist(insertAt),
    ];
    return QueueState._(
      entries,
      windowStart: 0,
      windowEnd: entries.length,
      currentIndex: base.currentIndex,
      shuffle: shuffle,
    );
  }

  /// Removes the loaded entry at window-relative [index]. An invalid index
  /// returns the same state. Removing the current entry selects its
  /// successor, or the new last entry; an empty result has a null index.
  QueueState removeAt(int index) {
    final loadedLength = windowEnd - windowStart;
    if (index < 0 || index >= loadedLength) return this;
    final base = _collapsed();
    final entries = List<QueueEntry>.of(base._entries)..removeAt(index);
    if (entries.isEmpty) {
      return QueueState._(
        const [],
        windowStart: 0,
        windowEnd: 0,
        currentIndex: null,
        shuffle: shuffle,
      );
    }
    final current = base.currentIndex;
    int? nextCurrent;
    if (current == null) {
      nextCurrent = null;
    } else if (index == current) {
      nextCurrent = index < entries.length ? index : entries.length - 1;
    } else if (index < current) {
      nextCurrent = current - 1;
    } else {
      nextCurrent = current;
    }
    return QueueState._(
      entries,
      windowStart: 0,
      windowEnd: entries.length,
      currentIndex: nextCurrent,
      shuffle: shuffle,
    );
  }

  /// Removes every occurrence of [trackId]. The current entry is retained by
  /// occurrence id when possible; when the current occurrence itself is
  /// removed, its successor (or the new last entry) is selected.
  QueueState removeTrack(String trackId) {
    var found = false;
    for (final entry in loadedEntries) {
      if (entry.track.id == trackId) {
        found = true;
        break;
      }
    }
    if (!found) {
      for (final entry in _entries) {
        if (entry.track.id == trackId) {
          found = true;
          break;
        }
      }
    }
    if (!found) return this;
    final base = _collapsed();
    final currentId = base.currentEntry?.id;
    final entries = [
      for (final entry in base._entries)
        if (entry.track.id != trackId) entry,
    ];
    if (entries.isEmpty) {
      return QueueState._(
        const [],
        windowStart: 0,
        windowEnd: 0,
        currentIndex: null,
        shuffle: shuffle,
      );
    }
    if (currentId != null) {
      final retained = entries.indexWhere((entry) => entry.id == currentId);
      if (retained >= 0) {
        return QueueState._(
          entries,
          windowStart: 0,
          windowEnd: entries.length,
          currentIndex: retained,
          shuffle: shuffle,
        );
      }
    }
    final current = base.currentIndex;
    final nextCurrent = current == null
        ? null
        : math.min(current, entries.length - 1);
    return QueueState._(
      entries,
      windowStart: 0,
      windowEnd: entries.length,
      currentIndex: nextCurrent,
      shuffle: shuffle,
    );
  }

  /// Moves the loaded entry at window-relative [oldIndex] to window-relative
  /// [newIndex], preserving the current occurrence by id. Invalid indices
  /// return the same state.
  QueueState reorder(int oldIndex, int newIndex) {
    final loadedLength = windowEnd - windowStart;
    if (oldIndex < 0 ||
        oldIndex >= loadedLength ||
        newIndex < 0 ||
        newIndex >= loadedLength) {
      return this;
    }
    final base = _collapsed();
    final currentId = base.currentEntry?.id;
    final entries = List<QueueEntry>.of(base._entries);
    final moved = entries.removeAt(oldIndex);
    entries.insert(newIndex, moved);
    int? nextCurrent = base.currentIndex;
    if (currentId != null) {
      nextCurrent = entries.indexWhere((entry) => entry.id == currentId);
      if (nextCurrent < 0) nextCurrent = base.currentIndex;
    }
    return QueueState._(
      entries,
      windowStart: 0,
      windowEnd: entries.length,
      currentIndex: nextCurrent,
      shuffle: shuffle,
    );
  }

  /// Selects the loaded occurrence with [entryId]. An unknown id returns the
  /// same state.
  QueueState selectEntry(String entryId) {
    final loaded = loadedEntries;
    final index = loaded.indexWhere((entry) => entry.id == entryId);
    if (index < 0) return this;
    if (index == currentIndex) return this;
    return QueueState._(
      _entries,
      windowStart: windowStart,
      windowEnd: windowEnd,
      currentIndex: index,
      shuffle: shuffle,
    );
  }

  /// Shuffles the loaded suffix after the current entry together with the
  /// unloaded tail, keeping the loaded prefix through the current occurrence
  /// in place. Every entry keeps its id and the loaded window size is
  /// unchanged.
  QueueState shuffleRemaining({math.Random? random}) {
    final rng = random ?? math.Random();
    final loadedLength = windowEnd - windowStart;
    final current = currentIndex;
    final prefixLength = current == null ? 0 : current + 1;
    if (prefixLength > loadedLength) return this;
    final pool = [
      ..._entries.sublist(windowStart + prefixLength, windowEnd),
      ..._entries.sublist(windowEnd),
    ];
    pool.shuffle(rng);
    final suffixLength = loadedLength - prefixLength;
    final newSuffix = pool.sublist(0, suffixLength.clamp(0, pool.length));
    final newTail = pool.sublist(suffixLength.clamp(0, pool.length));
    return QueueState._(
      [
        ..._entries.sublist(0, windowStart + prefixLength),
        ...newSuffix,
        ...newTail,
      ],
      windowStart: windowStart,
      windowEnd: windowStart + prefixLength + newSuffix.length,
      currentIndex: current,
      shuffle: shuffle,
    );
  }

  /// Enables or disables the shuffle flag without reordering entries.
  /// Enabling alone does not shuffle; disabling preserves the current order.
  QueueState withShuffle(bool enabled) {
    if (enabled == shuffle) return this;
    return QueueState._(
      _entries,
      windowStart: windowStart,
      windowEnd: windowEnd,
      currentIndex: currentIndex,
      shuffle: enabled,
    );
  }

  /// Loads up to 100 more entries from the tail into the window, retaining
  /// all ids and the current index.
  QueueState extend() {
    if (windowEnd >= _entries.length) return this;
    final end = math.min(_entries.length, windowEnd + _queueExtensionSize);
    return QueueState._(
      _entries,
      windowStart: windowStart,
      windowEnd: end,
      currentIndex: currentIndex,
      shuffle: shuffle,
    );
  }

  /// Collapses the state to its loaded entries: the unloaded tail is
  /// discarded and the window restarts at zero with the same current entry.
  QueueState _collapsed() {
    if (windowStart == 0 && windowEnd == _entries.length) return this;
    final loaded = _entries.sublist(
      windowStart.clamp(0, _entries.length),
      windowEnd.clamp(0, _entries.length),
    );
    return QueueState._(
      loaded,
      windowStart: 0,
      windowEnd: loaded.length,
      currentIndex: currentIndex,
      shuffle: shuffle,
    );
  }
}
