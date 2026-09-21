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

/// Compact "Sort by" dropdown used above collection grids and song lists.
class SortByDropdown<T extends Enum> extends StatelessWidget {
  const SortByDropdown({
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
    final textStyle = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: SpotifinColors.textMuted);
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.sort_rounded,
              size: 18,
              color: SpotifinColors.textMuted,
            ),
            const SizedBox(width: 8),
            Text('Sort by', style: textStyle),
            const SizedBox(width: 8),
            Tooltip(
              message: tooltip,
              child: DropdownButtonHideUnderline(
                child: DropdownButton<T>(
                  value: value,
                  isDense: true,
                  style: Theme.of(context).textTheme.bodySmall,
                  items: [
                    for (final option in values)
                      DropdownMenuItem<T>(
                        value: option,
                        child: Text(labelOf(option)),
                      ),
                  ],
                  onChanged: onChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
