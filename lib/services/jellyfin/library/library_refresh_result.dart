import '../../../storage/database.dart';

/// Explicit outcome of a library refresh.
///
/// A committed catalog means database application finished for the
/// requesting lease; failure and stale work are never reported as an empty
/// successful catalog. The underlying [JellyfinException] is preserved so
/// callers can keep their 401/expiry handling.
class LibraryRefreshResult {
  const LibraryRefreshResult._({
    required this.kind,
    this.catalog = const [],
    this.pendingBlocked = false,
    this.playlistError,
    this.error,
  });

  const LibraryRefreshResult.committed(
    List<Track> catalog, {
    bool pendingBlocked = false,
    Object? playlistError,
  }) : this._(
         kind: LibraryRefreshKind.committed,
         catalog: catalog,
         pendingBlocked: pendingBlocked,
         playlistError: playlistError,
       );

  const LibraryRefreshResult.failed(Object error)
    : this._(kind: LibraryRefreshKind.failed, error: error);

  const LibraryRefreshResult.stale() : this._(kind: LibraryRefreshKind.stale);

  final LibraryRefreshKind kind;

  /// Effective catalog read after commit. Only meaningful for [committed].
  final List<Track> catalog;

  /// True when pending delivery blocked but the snapshot still committed.
  final bool pendingBlocked;

  /// Non-fatal playlist-stage failure accompanying a committed catalog.
  final Object? playlistError;

  /// Fatal failure for [failed] results.
  final Object? error;

  bool get isCommitted => kind == LibraryRefreshKind.committed;
  bool get isFailed => kind == LibraryRefreshKind.failed;
  bool get isStale => kind == LibraryRefreshKind.stale;
}

enum LibraryRefreshKind { committed, failed, stale }
