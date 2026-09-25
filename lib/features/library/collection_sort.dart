import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../storage/database.dart';
import '../coverflow/coverflow_model.dart';

/// Ordering options for collection grids (albums, artists, playlists).
enum CollectionSort { nameAsc, nameDesc, mostSongs, fewestSongs }

extension CollectionSortX on CollectionSort {
  String get label => switch (this) {
    CollectionSort.nameAsc => 'Name A–Z',
    CollectionSort.nameDesc => 'Name Z–A',
    CollectionSort.mostSongs => 'Most songs',
    CollectionSort.fewestSongs => 'Fewest songs',
  };
}

/// Ordering options for song lists inside collections.
enum TrackSort {
  defaultOrder,
  nameAsc,
  nameDesc,
  artistAsc,
  albumAsc,
  longestFirst,
  shortestFirst,
  recentlyAdded,
}

extension TrackSortX on TrackSort {
  String get label => switch (this) {
    TrackSort.defaultOrder => 'Default order',
    TrackSort.nameAsc => 'Title A–Z',
    TrackSort.nameDesc => 'Title Z–A',
    TrackSort.artistAsc => 'Artist A–Z',
    TrackSort.albumAsc => 'Album A–Z',
    TrackSort.longestFirst => 'Longest first',
    TrackSort.shortestFirst => 'Shortest first',
    TrackSort.recentlyAdded => 'Recently added',
  };
}

/// Ordering options for the albums tab inside an artist collection.
/// [featured] keeps the existing behaviour: full albums first, then by
/// release date, then by name.
enum ArtistAlbumSort { featured, nameAsc, nameDesc, mostSongs, fewestSongs }

extension ArtistAlbumSortX on ArtistAlbumSort {
  String get label => switch (this) {
    ArtistAlbumSort.featured => 'Featured',
    ArtistAlbumSort.nameAsc => 'Name A–Z',
    ArtistAlbumSort.nameDesc => 'Name Z–A',
    ArtistAlbumSort.mostSongs => 'Most songs',
    ArtistAlbumSort.fewestSongs => 'Fewest songs',
  };
}

class CollectionSortController extends Notifier<CollectionSort> {
  @override
  CollectionSort build() => CollectionSort.nameAsc;

  void set(CollectionSort sort) {
    if (state != sort) state = sort;
  }
}

class TrackSortController extends Notifier<TrackSort> {
  @override
  TrackSort build() => TrackSort.defaultOrder;

  void set(TrackSort sort) {
    if (state != sort) state = sort;
  }
}

class ArtistAlbumSortController extends Notifier<ArtistAlbumSort> {
  @override
  ArtistAlbumSort build() => ArtistAlbumSort.featured;

  void set(ArtistAlbumSort sort) {
    if (state != sort) state = sort;
  }
}

final libraryAlbumSortProvider =
    NotifierProvider<CollectionSortController, CollectionSort>(
      CollectionSortController.new,
    );
final libraryArtistSortProvider =
    NotifierProvider<CollectionSortController, CollectionSort>(
      CollectionSortController.new,
    );
final libraryPlaylistSortProvider =
    NotifierProvider<CollectionSortController, CollectionSort>(
      CollectionSortController.new,
    );
final libraryTrackSortProvider =
    NotifierProvider<TrackSortController, TrackSort>(TrackSortController.new);
final collectionTrackSortProvider =
    NotifierProvider<TrackSortController, TrackSort>(TrackSortController.new);
final artistAlbumsSortProvider =
    NotifierProvider<ArtistAlbumSortController, ArtistAlbumSort>(
      ArtistAlbumSortController.new,
    );

int _compareNames(String a, String b) =>
    a.toLowerCase().compareTo(b.toLowerCase());

/// Sorts collection grid entries without mutating [entries].
/// Song-count orders tie-break by name so the result is deterministic.
List<MapEntry<String, List<Track>>> sortCollectionEntries(
  List<MapEntry<String, List<Track>>> entries,
  CollectionSort sort,
) {
  final sorted = [...entries];
  switch (sort) {
    case CollectionSort.nameAsc:
      sorted.sort((a, b) => _compareNames(a.key, b.key));
    case CollectionSort.nameDesc:
      sorted.sort((a, b) => _compareNames(b.key, a.key));
    case CollectionSort.mostSongs:
      sorted.sort((a, b) {
        final byCount = b.value.length.compareTo(a.value.length);
        if (byCount != 0) return byCount;
        return _compareNames(a.key, b.key);
      });
    case CollectionSort.fewestSongs:
      sorted.sort((a, b) {
        final byCount = a.value.length.compareTo(b.value.length);
        if (byCount != 0) return byCount;
        return _compareNames(a.key, b.key);
      });
  }
  return sorted;
}

/// Sorts a song list without mutating [tracks].
/// [defaultOrder] preserves the caller-provided order (e.g. date-added).
List<Track> sortTracks(List<Track> tracks, TrackSort sort) {
  if (sort == TrackSort.defaultOrder) return [...tracks];
  final sorted = [...tracks];
  switch (sort) {
    case TrackSort.defaultOrder:
      break;
    case TrackSort.nameAsc:
      sorted.sort((a, b) => _compareNames(a.name, b.name));
    case TrackSort.nameDesc:
      sorted.sort((a, b) => _compareNames(b.name, a.name));
    case TrackSort.artistAsc:
      sorted.sort((a, b) {
        final byArtist = _compareNames(a.artist, b.artist);
        if (byArtist != 0) return byArtist;
        return _compareNames(a.name, b.name);
      });
    case TrackSort.albumAsc:
      sorted.sort((a, b) {
        final byAlbum = _compareNames(a.album, b.album);
        if (byAlbum != 0) return byAlbum;
        return _compareNames(a.name, b.name);
      });
    case TrackSort.longestFirst:
      sorted.sort((a, b) {
        final byDuration = b.durationTicks.compareTo(a.durationTicks);
        if (byDuration != 0) return byDuration;
        return _compareNames(a.name, b.name);
      });
    case TrackSort.shortestFirst:
      sorted.sort((a, b) {
        final byDuration = a.durationTicks.compareTo(b.durationTicks);
        if (byDuration != 0) return byDuration;
        return _compareNames(a.name, b.name);
      });
    case TrackSort.recentlyAdded:
      sorted.sort((a, b) {
        final aDate = a.dateCreated;
        final bDate = b.dateCreated;
        if (aDate != null && bDate != null) {
          final byDate = bDate.compareTo(aDate);
          if (byDate != 0) return byDate;
        } else if (aDate != null) {
          return -1;
        } else if (bDate != null) {
          return 1;
        }
        return _compareNames(a.name, b.name);
      });
  }
  return sorted;
}

/// Sorts coverflow collection items to match the grid order.
List<CoverflowItem> sortCoverflowCollections(
  List<CoverflowItem> items,
  CollectionSort sort,
) {
  final sorted = [...items];
  switch (sort) {
    case CollectionSort.nameAsc:
      sorted.sort((a, b) => _compareNames(a.title, b.title));
    case CollectionSort.nameDesc:
      sorted.sort((a, b) => _compareNames(b.title, a.title));
    case CollectionSort.mostSongs:
      sorted.sort((a, b) {
        final byCount = b.tracks.length.compareTo(a.tracks.length);
        if (byCount != 0) return byCount;
        return _compareNames(a.title, b.title);
      });
    case CollectionSort.fewestSongs:
      sorted.sort((a, b) {
        final byCount = a.tracks.length.compareTo(b.tracks.length);
        if (byCount != 0) return byCount;
        return _compareNames(a.title, b.title);
      });
  }
  return sorted;
}

/// Sorts playlists alongside their resolved tracks without mutating inputs.
List<Playlist> sortPlaylists(
  List<Playlist> playlists,
  Map<String, List<Track>> tracksByPlaylistId,
  CollectionSort sort,
) {
  final sorted = [...playlists];
  int countOf(Playlist playlist) =>
      tracksByPlaylistId[playlist.id]?.length ?? 0;
  switch (sort) {
    case CollectionSort.nameAsc:
      sorted.sort((a, b) => _compareNames(a.name, b.name));
    case CollectionSort.nameDesc:
      sorted.sort((a, b) => _compareNames(b.name, a.name));
    case CollectionSort.mostSongs:
      sorted.sort((a, b) {
        final byCount = countOf(b).compareTo(countOf(a));
        if (byCount != 0) return byCount;
        return _compareNames(a.name, b.name);
      });
    case CollectionSort.fewestSongs:
      sorted.sort((a, b) {
        final byCount = countOf(a).compareTo(countOf(b));
        if (byCount != 0) return byCount;
        return _compareNames(a.name, b.name);
      });
  }
  return sorted;
}

/// Compact icon-based sort control for the library toolbar.
///
/// Sits alongside the Coverflow toggle and other toolbar actions, using the
/// same [IconButton]-based sizing, spacing, color, and interaction states.
/// The current option is marked with a check in the menu; sort behaviour and
/// providers are unchanged.
class SortMenuButton<T extends Enum> extends StatelessWidget {
  const SortMenuButton({
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
    this.tooltip = 'Sort by',
    super.key,
  });

  final T value;
  final List<T> values;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<T>(
      icon: const Icon(Icons.sort_rounded),
      iconColor: SpotifinColors.textMuted,
      tooltip: tooltip,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final option in values)
          PopupMenuItem<T>(
            value: option,
            child: Row(
              children: [
                if (option == value)
                  const Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: SpotifinColors.accent,
                  )
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(labelOf(option), overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Tab-aware sort action for the top library toolbar.
///
/// Reads the surrounding DefaultTabController (same as the coverflow header
/// toggle) so the menu always edits the sort of the visible
/// library tab while living alongside the Coverflow control in the header.
class LibrarySortAction extends StatelessWidget {
  const LibrarySortAction({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final index = controller.index.clamp(0, 3);
        return switch (index) {
          0 => const _LibraryTrackSortButton(),
          1 => const _LibraryAlbumSortButton(),
          2 => const _LibraryArtistSortButton(),
          _ => const _LibraryPlaylistSortButton(),
        };
      },
    );
  }
}

class _LibraryTrackSortButton extends ConsumerWidget {
  const _LibraryTrackSortButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(libraryTrackSortProvider);
    return SortMenuButton<TrackSort>(
      value: sort,
      values: TrackSort.values,
      labelOf: (option) => option.label,
      tooltip: 'Sort songs',
      onChanged: (option) {
        if (option != null) {
          ref.read(libraryTrackSortProvider.notifier).set(option);
        }
      },
    );
  }
}

class _LibraryAlbumSortButton extends ConsumerWidget {
  const _LibraryAlbumSortButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(libraryAlbumSortProvider);
    return SortMenuButton<CollectionSort>(
      value: sort,
      values: CollectionSort.values,
      labelOf: (option) => option.label,
      tooltip: 'Sort albums',
      onChanged: (option) {
        if (option != null) {
          ref.read(libraryAlbumSortProvider.notifier).set(option);
        }
      },
    );
  }
}

class _LibraryArtistSortButton extends ConsumerWidget {
  const _LibraryArtistSortButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(libraryArtistSortProvider);
    return SortMenuButton<CollectionSort>(
      value: sort,
      values: CollectionSort.values,
      labelOf: (option) => option.label,
      tooltip: 'Sort artists',
      onChanged: (option) {
        if (option != null) {
          ref.read(libraryArtistSortProvider.notifier).set(option);
        }
      },
    );
  }
}

class _LibraryPlaylistSortButton extends ConsumerWidget {
  const _LibraryPlaylistSortButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(libraryPlaylistSortProvider);
    return SortMenuButton<CollectionSort>(
      value: sort,
      values: CollectionSort.values,
      labelOf: (option) => option.label,
      tooltip: 'Sort playlists',
      onChanged: (option) {
        if (option != null) {
          ref.read(libraryPlaylistSortProvider.notifier).set(option);
        }
      },
    );
  }
}

class CollectionSortAction extends StatelessWidget {
  const CollectionSortAction({required this.artistTabs, super.key});

  final bool artistTabs;

  @override
  Widget build(BuildContext context) {
    if (!artistTabs) return const _CollectionTrackSortButton();
    final controller = DefaultTabController.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => controller.index == 0
          ? const _CollectionTrackSortButton()
          : const _ArtistAlbumSortButton(),
    );
  }
}

class _CollectionTrackSortButton extends ConsumerWidget {
  const _CollectionTrackSortButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(collectionTrackSortProvider);
    return SortMenuButton<TrackSort>(
      value: sort,
      values: TrackSort.values,
      labelOf: (option) => option.label,
      tooltip: 'Sort collection songs',
      onChanged: (option) {
        if (option != null) {
          ref.read(collectionTrackSortProvider.notifier).set(option);
        }
      },
    );
  }
}

class _ArtistAlbumSortButton extends ConsumerWidget {
  const _ArtistAlbumSortButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(artistAlbumsSortProvider);
    return SortMenuButton<ArtistAlbumSort>(
      value: sort,
      values: ArtistAlbumSort.values,
      labelOf: (option) => option.label,
      tooltip: 'Sort artist albums',
      onChanged: (option) {
        if (option != null) {
          ref.read(artistAlbumsSortProvider.notifier).set(option);
        }
      },
    );
  }
}
