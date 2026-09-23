/// Mobile queue view helpers.
///
/// The full playback queue keeps every queued track. The visible queue is a
/// focused view on top of it: the currently playing track is first, followed
/// by the remaining upcoming tracks. Played tracks remain in playback history.
class MobileQueueView {
  const MobileQueueView._();

  /// Returns the mobile view of [queue]: the slice starting at
  /// [currentIndex]. Played entries before [currentIndex] are hidden.
  ///
  /// An empty queue stays empty. A missing or out-of-range [currentIndex]
  /// (for example before sources load) falls back to the full queue so the
  /// UI never crashes on a transient null.
  static List<T> upcoming<T>(List<T> queue, int? currentIndex) {
    if (queue.isEmpty) return const [];
    final base = offsetFor(currentIndex, queue.length);
    if (base <= 0) return List<T>.unmodifiable(queue);
    return List<T>.unmodifiable(queue.sublist(base));
  }

  /// Base full-queue index backing mobile index 0.
  static int offsetFor(int? currentIndex, int length) {
    if (length <= 0) return 0;
    if (currentIndex == null || currentIndex < 0 || currentIndex >= length) {
      return 0;
    }
    return currentIndex;
  }

  /// Translates a mobile list index to a full-queue index.
  ///
  /// Returns -1 when [mobileIndex] is out of range.
  static int toFullIndex(int mobileIndex, int? currentIndex, int length) {
    if (mobileIndex < 0 || length <= 0) return -1;
    final full = offsetFor(currentIndex, length) + mobileIndex;
    if (full < 0 || full >= length) return -1;
    return full;
  }

  /// Translates a full-queue index to a mobile list index.
  ///
  /// Returns -1 for entries that are hidden because they were already played.
  static int toMobileIndex(int fullIndex, int? currentIndex, int length) {
    if (fullIndex < 0 || fullIndex >= length) return -1;
    final mobile = fullIndex - offsetFor(currentIndex, length);
    return mobile < 0 ? -1 : mobile;
  }

  /// Translates a mobile reorder into full-queue indices.
  ///
  /// Returns null when the move involves mobile index 0 (the current track
  /// stays pinned first) or when either side is out of range, so callers can
  /// ignore the gesture instead of corrupting the upcoming order.
  static (int, int)? reorderFullIndices(
    int oldMobileIndex,
    int newMobileIndex,
    int? currentIndex,
    int length,
  ) {
    if (oldMobileIndex <= 0 || newMobileIndex <= 0) return null;
    final base = offsetFor(currentIndex, length);
    final oldFull = base + oldMobileIndex;
    final newFull = base + newMobileIndex;
    if (oldFull < 0 || oldFull >= length || newFull < 0 || newFull >= length) {
      return null;
    }
    return (oldFull, newFull);
  }
}
