import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../services/playback/playback_service.dart';
import '../../storage/database.dart';
import '../../storage/track_artists.dart';
import '../common/artwork.dart';
import '../common/album_context_menu.dart';
import '../common/collection_download_button.dart';
import '../common/design_system.dart';
import '../common/playlist_artwork.dart';
import '../common/playlist_context_menu.dart';
import '../common/track_tile.dart';
import '../coverflow/coverflow_controller.dart';
import '../coverflow/coverflow_header_toggle.dart';
import '../coverflow/coverflow_model.dart';
import '../coverflow/coverflow_section.dart';
import '../coverflow/coverflow_stage.dart';
import '../coverflow/mobile_coverflow_scope.dart';
import 'collection_sort.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key, this.initialTabIndex = 0});

  final int initialTabIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final desktop =
        MediaQuery.sizeOf(context).width >= SpotifinBreakpoints.rail;
    return DefaultTabController(
      length: 4,
      initialIndex: initialTabIndex.clamp(0, 3),
      child: Scaffold(
        appBar: AppBar(
          title: desktop ? null : const Text('Your library'),
          toolbarHeight: desktop ? 0 : kToolbarHeight,
        ),
        body: StreamBuilder<List<Track>>(
          stream: ref.watch(tracksByDateAddedStreamProvider),
          builder: (context, trackSnapshot) {
            final tracks = trackSnapshot.data ?? const [];
            return NestedScrollView(
              headerSliverBuilder: (context, _) => [
                SliverToBoxAdapter(
                  child: _CollectionHeader(
                    title: 'Your library',
                    tracks: tracks,
                    kind: CollectionKind.library,
                    coverflowToggle: CoverflowHeaderToggle(
                      viewIds: [
                        for (final source in CoverflowSource.values)
                          libraryCoverflowViewId(source),
                        'library:playlists',
                      ],
                    ),
                    artwork: PlaylistArtwork(
                      tracks: tracks,
                      size: 160,
                      borderRadius: SpotifinRadii.card,
                    ),
                  ),
                ),
                const SliverPersistentHeader(
                  pinned: true,
                  delegate: _PinnedTabBar(
                    SpotifinTabBar(
                      labels: ['Songs', 'Albums', 'Artists', 'Playlists'],
                    ),
                  ),
                ),
              ],
              body: TabBarView(
                children: [
                  _TrackList(tracks: tracks),
                  _AlbumList(tracks: tracks),
                  _ArtistList(tracks: tracks),
                  _PlaylistsTab(tracks: tracks),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TrackList extends ConsumerWidget {
  const _TrackList({required this.tracks});
  final List<Track> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(libraryTrackSortProvider);
    final sorted = sortTracks(tracks, sort);
    final items = trackCoverflowItems(sorted);
    return MobileCoverflowScope(
      viewId: libraryCoverflowViewId(CoverflowSource.tracks),
      tabIndex: 0,
      collection: MobileCoverflowCollection(
        items: items,
        contextTracks: sorted,
        playback: MobileCoverflowPlayback.tracks,
      ),
      child: CoverflowSection(
        viewId: libraryCoverflowViewId(CoverflowSource.tracks),
        items: items,
        onCenterTap: (item) =>
            ref.read(playbackProvider).playTrack(item.tracks.single, sorted),
        list: Column(
          children: [
            SortByDropdown<TrackSort>(
              value: sort,
              values: TrackSort.values,
              labelOf: (option) => option.label,
              tooltip: 'Sort songs',
              onChanged: (option) {
                if (option != null) {
                  ref.read(libraryTrackSortProvider.notifier).set(option);
                }
              },
            ),
            Expanded(
              child: ListView.builder(
                key: const PageStorageKey('library-songs'),
                padding: EdgeInsets.only(
                  bottom: SpotifinChromeInsets.bottomOf(context),
                ),
                itemCount: sorted.length,
                itemBuilder: (context, index) =>
                    TrackTile(track: sorted[index], contextTracks: sorted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlbumList extends ConsumerWidget {
  const _AlbumList({required this.tracks});
  final List<Track> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(libraryAlbumSortProvider);
    final entries = sortCollectionEntries(_albumEntries(tracks), sort);
    final items = sortCoverflowCollections(albumCoverflowItems(tracks), sort);
    return MobileCoverflowScope(
      viewId: libraryCoverflowViewId(CoverflowSource.albums),
      tabIndex: 1,
      collection: MobileCoverflowCollection(
        items: items,
        contextTracks: tracks,
        playback: MobileCoverflowPlayback.collection,
      ),
      child: CoverflowSection(
        viewId: libraryCoverflowViewId(CoverflowSource.albums),
        items: items,
        onCenterTap: (item) => item.tracks.isEmpty
            ? null
            : ref
                  .read(playbackProvider)
                  .replaceQueue(item.tracks, shuffle: false),
        list: Column(
          children: [
            SortByDropdown<CollectionSort>(
              value: sort,
              values: CollectionSort.values,
              labelOf: (option) => option.label,
              tooltip: 'Sort albums',
              onChanged: (option) {
                if (option != null) {
                  ref.read(libraryAlbumSortProvider.notifier).set(option);
                }
              },
            ),
            Expanded(child: _CollectionGrid(entries: entries)),
          ],
        ),
      ),
    );
  }
}

List<MapEntry<String, List<Track>>> _albumEntries(List<Track> tracks) {
  final groups = groupBy(
    tracks.where((track) => track.album.isNotEmpty),
    (Track track) => track.albumId ?? 'album:${track.album}',
  );
  final entries = [
    for (final group in groups.values) MapEntry(group.first.album, group),
  ];
  return entries.sortedBy((entry) => entry.key.toLowerCase());
}

class _ArtistList extends ConsumerWidget {
  const _ArtistList({required this.tracks});
  final List<Track> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(libraryArtistSortProvider);
    final groups = <String, _ArtistGroup>{};
    for (final track in tracks) {
      for (final artist in track.artistCredits) {
        final key = artist.id ?? 'name:${artist.name}';
        (groups[key] ??= _ArtistGroup(artist.name)).tracks.add(track);
      }
    }
    final entries = sortCollectionEntries([
      for (final group in groups.values) MapEntry(group.name, group.tracks),
    ], sort);
    final items = sortCoverflowCollections(artistCoverflowItems(tracks), sort);
    return MobileCoverflowScope(
      viewId: libraryCoverflowViewId(CoverflowSource.artists),
      tabIndex: 2,
      collection: MobileCoverflowCollection(
        items: items,
        contextTracks: tracks,
        playback: MobileCoverflowPlayback.collection,
      ),
      child: CoverflowSection(
        viewId: libraryCoverflowViewId(CoverflowSource.artists),
        items: items,
        onCenterTap: (item) => item.tracks.isEmpty
            ? null
            : ref
                  .read(playbackProvider)
                  .replaceQueue(item.tracks, shuffle: false),
        list: Column(
          children: [
            SortByDropdown<CollectionSort>(
              value: sort,
              values: CollectionSort.values,
              labelOf: (option) => option.label,
              tooltip: 'Sort artists',
              onChanged: (option) {
                if (option != null) {
                  ref.read(libraryArtistSortProvider.notifier).set(option);
                }
              },
            ),
            Expanded(child: _CollectionGrid(entries: entries, artist: true)),
          ],
        ),
      ),
    );
  }
}

class _ArtistGroup {
  _ArtistGroup(this.name);

  final String name;
  final List<Track> tracks = [];
}

class _CollectionGrid extends StatelessWidget {
  const _CollectionGrid({required this.entries, this.artist = false});
  final List<MapEntry<String, List<Track>>> entries;
  final bool artist;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const SpotifinEmptyState(
        icon: Icons.library_music_outlined,
        title: 'Nothing here yet',
      );
    }
    return spotifinGrid(
      itemCount: entries.length,
      itemBuilder: (context, index) => _CollectionCard(
        title: entries[index].key,
        tracks: entries[index].value,
        artist: artist,
        menu: !artist,
      ),
    );
  }
}

class _CollectionCard extends ConsumerWidget {
  const _CollectionCard({
    required this.title,
    required this.tracks,
    this.artist = false,
    this.menu = false,
  });
  final String title;
  final List<Track> tracks;
  final bool artist;
  final bool menu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = tracks.first;
    final card = SpotifinCollectionCard(
      artwork: LayoutBuilder(
        builder: (context, constraints) => Artwork(
          itemId: first.albumId ?? first.id,
          size: constraints.biggest.shortestSide,
          borderRadius: artist
              ? constraints.biggest.shortestSide / 2
              : SpotifinRadii.small,
        ),
      ),
      title: title,
      subtitle: '${tracks.length} songs',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CollectionScreen(
            title: title,
            tracks: tracks,
            kind: artist ? CollectionKind.artist : CollectionKind.album,
          ),
        ),
      ),
      onPlay: tracks.isEmpty
          ? null
          : () => ref.read(playbackProvider).replaceQueue(tracks),
    );
    if (!menu) return card;
    return AlbumContextMenu(title: title, tracks: tracks, child: card);
  }
}

class _ArtistAlbumsTab extends ConsumerWidget {
  const _ArtistAlbumsTab({
    required this.tracks,
    required this.viewId,
    super.key,
  });
  final List<Track> tracks;
  final String viewId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(artistAlbumsSortProvider);
    return StreamBuilder<Map<String, DateTime>>(
      stream: ref.watch(albumDatesStreamProvider),
      builder: (context, snapshot) {
        final albums = _sortedArtistAlbums(
          tracks,
          snapshot.data ?? const {},
          sort,
        );
        if (albums.isEmpty) {
          return const SpotifinEmptyState(
            icon: Icons.library_music_outlined,
            title: 'Nothing here yet',
          );
        }
        final items = albumCoverflowItems(tracks);
        return MobileCoverflowScope(
          viewId: viewId,
          tabIndex: 1,
          collection: MobileCoverflowCollection(
            items: items,
            contextTracks: tracks,
            playback: MobileCoverflowPlayback.collection,
          ),
          child: CoverflowSection(
            viewId: viewId,
            items: items,
            onCenterTap: (item) => item.tracks.isEmpty
                ? null
                : ref
                      .read(playbackProvider)
                      .replaceQueue(item.tracks, shuffle: false),
            list: Column(
              children: [
                SortByDropdown<ArtistAlbumSort>(
                  value: sort,
                  values: ArtistAlbumSort.values,
                  labelOf: (option) => option.label,
                  tooltip: 'Sort artist albums',
                  onChanged: (option) {
                    if (option != null) {
                      ref.read(artistAlbumsSortProvider.notifier).set(option);
                    }
                  },
                ),
                Expanded(
                  child: spotifinGrid(
                    itemCount: albums.length,
                    itemBuilder: (context, index) => _CollectionCard(
                      title: albums[index].name,
                      tracks: albums[index].tracks,
                      menu: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AlbumGroup {
  const _AlbumGroup({required this.name, this.albumId, required this.tracks});
  final String name;
  final String? albumId;
  final List<Track> tracks;

  bool get isFullAlbum => tracks.length > 5;

  DateTime? get trackDate {
    DateTime? earliest;
    for (final track in tracks) {
      final date = track.premiereDate;
      if (date == null) continue;
      if (earliest == null || date.isBefore(earliest)) earliest = date;
    }
    return earliest;
  }
}

DateTime? _releaseDate(_AlbumGroup album, Map<String, DateTime> albumDates) {
  final albumDate = album.albumId == null ? null : albumDates[album.albumId!];
  if (albumDate != null && !_isYearOnly(albumDate)) return albumDate;
  return album.trackDate ?? albumDate;
}

bool _isYearOnly(DateTime date) => date.month == 1 && date.day == 1;

List<_AlbumGroup> _sortedArtistAlbums(
  List<Track> tracks,
  Map<String, DateTime> albumDates, [
  ArtistAlbumSort sort = ArtistAlbumSort.featured,
]) {
  final grouped = <String, _AlbumGroup>{};
  for (final track in tracks) {
    if (track.album.isEmpty) continue;
    final key = track.albumId ?? track.album;
    grouped
        .putIfAbsent(
          key,
          () => _AlbumGroup(
            name: track.album,
            albumId: track.albumId,
            tracks: [],
          ),
        )
        .tracks
        .add(track);
  }
  final albums = grouped.values.toList();
  switch (sort) {
    case ArtistAlbumSort.featured:
      albums.sort((a, b) => _byFullAlbumThenDate(a, b, albumDates));
    case ArtistAlbumSort.nameAsc:
      albums.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    case ArtistAlbumSort.nameDesc:
      albums.sort(
        (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
      );
    case ArtistAlbumSort.mostSongs:
      albums.sort((a, b) {
        final byCount = b.tracks.length.compareTo(a.tracks.length);
        if (byCount != 0) return byCount;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    case ArtistAlbumSort.fewestSongs:
      albums.sort((a, b) {
        final byCount = a.tracks.length.compareTo(b.tracks.length);
        if (byCount != 0) return byCount;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  }
  return albums;
}

int _byFullAlbumThenDate(
  _AlbumGroup a,
  _AlbumGroup b,
  Map<String, DateTime> albumDates,
) {
  if (a.isFullAlbum != b.isFullAlbum) return a.isFullAlbum ? -1 : 1;
  final aDate = _releaseDate(a, albumDates);
  final bDate = _releaseDate(b, albumDates);
  if (aDate != null && bDate != null) {
    final byDate = bDate.compareTo(aDate);
    if (byDate != 0) return byDate;
  } else if (aDate != null) {
    return -1;
  } else if (bDate != null) {
    return 1;
  }
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

class _PlaylistsTab extends ConsumerWidget {
  const _PlaylistsTab({required this.tracks});
  final List<Track> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(libraryPlaylistSortProvider);
    return StreamBuilder<List<Playlist>>(
      stream: ref.watch(playlistsStreamProvider),
      builder: (context, snapshot) {
        final stored = snapshot.data ?? const <Playlist>[];
        final byId = {for (final track in tracks) track.id: track};
        if (stored.isEmpty) {
          return const SpotifinEmptyState(
            icon: Icons.queue_music_rounded,
            title: 'No playlists yet',
            message: 'Save your current queue to create one.',
          );
        }
        final tracksByPlaylistId = {
          for (final playlist in stored)
            playlist.id: tracksInPlaylist(playlist, byId),
        };
        final playlists = sortPlaylists(stored, tracksByPlaylistId, sort);
        final items = [
          for (final playlist in playlists)
            CoverflowItem(
              id: 'playlist:${playlist.id}',
              title: playlist.name,
              subtitle: '${tracksByPlaylistId[playlist.id]?.length ?? 0} songs',
              artItemId: _playlistArtItemId(
                tracksByPlaylistId[playlist.id] ?? const [],
                playlist.id,
              ),
              tracks: tracksByPlaylistId[playlist.id] ?? const [],
              collection: true,
            ),
        ];
        return MobileCoverflowScope(
          viewId: 'library:playlists',
          tabIndex: 3,
          collection: MobileCoverflowCollection(
            items: items,
            contextTracks: tracks,
            playback: MobileCoverflowPlayback.collection,
          ),
          child: CoverflowSection(
            viewId: 'library:playlists',
            items: items,
            onCenterTap: (item) => item.tracks.isEmpty
                ? null
                : ref
                      .read(playbackProvider)
                      .replaceQueue(item.tracks, shuffle: false),
            list: Column(
              children: [
                SortByDropdown<CollectionSort>(
                  value: sort,
                  values: CollectionSort.values,
                  labelOf: (option) => option.label,
                  tooltip: 'Sort playlists',
                  onChanged: (option) {
                    if (option != null) {
                      ref
                          .read(libraryPlaylistSortProvider.notifier)
                          .set(option);
                    }
                  },
                ),
                Expanded(
                  child: spotifinGrid(
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      final playlistTracks =
                          tracksByPlaylistId[playlist.id] ?? const [];
                      return PlaylistContextMenu(
                        playlist: playlist,
                        tracks: playlistTracks,
                        child: SpotifinCollectionCard(
                          artwork: LayoutBuilder(
                            builder: (context, constraints) => PlaylistArtwork(
                              tracks: playlistTracks,
                              size: constraints.biggest.shortestSide,
                              borderRadius: SpotifinRadii.small,
                            ),
                          ),
                          title: playlist.name,
                          subtitle: '${playlistTracks.length} songs',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => CollectionScreen(
                                title: playlist.name,
                                tracks: playlistTracks,
                                kind: CollectionKind.playlist,
                                artwork: PlaylistArtwork(
                                  tracks: playlistTracks,
                                  size: 160,
                                  borderRadius: SpotifinRadii.card,
                                ),
                              ),
                            ),
                          ),
                          onPlay: playlistTracks.isEmpty
                              ? null
                              : () => ref
                                    .read(playbackProvider)
                                    .replaceQueue(playlistTracks),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _playlistArtItemId(List<Track> tracks, String fallbackId) {
  if (tracks.isEmpty) return fallbackId;
  final first = tracks.first;
  return first.albumId ?? first.id;
}

enum CollectionKind { library, album, artist, playlist }

extension CollectionKindX on CollectionKind {
  String get label => switch (this) {
    CollectionKind.library => 'LIBRARY',
    CollectionKind.album => 'ALBUM',
    CollectionKind.artist => 'ARTIST',
    CollectionKind.playlist => 'PLAYLIST',
  };

  IconData get fallbackIcon => switch (this) {
    CollectionKind.library => Icons.library_music_rounded,
    CollectionKind.album => Icons.album_rounded,
    CollectionKind.artist => Icons.person_rounded,
    CollectionKind.playlist => Icons.queue_music_rounded,
  };

  bool get hasArtistTabs => this == CollectionKind.artist;
}

Duration? _collectionDuration(List<Track> tracks) {
  var microseconds = 0;
  for (final track in tracks) {
    if (track.durationTicks > 0) microseconds += track.durationTicks ~/ 10;
  }
  if (microseconds <= 0) return null;
  return Duration(microseconds: microseconds);
}

String _formatCollectionDuration(Duration duration) {
  final totalMinutes = duration.inMinutes;
  if (totalMinutes < 60) return '$totalMinutes min';
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (minutes == 0) return '$hours hr';
  return '$hours hr $minutes min';
}

String? _albumArtist(List<Track> tracks) {
  final artists = {
    for (final track in tracks)
      if (track.artist.trim().isNotEmpty) track.artist.trim(),
  };
  if (artists.isEmpty || artists.contains('Unknown artist')) {
    artists.remove('Unknown artist');
    if (artists.isEmpty) return null;
  }
  if (artists.length == 1) return artists.single;
  return 'Various artists';
}

DateTime? _albumReleaseDate(
  List<Track> tracks,
  Map<String, DateTime> albumDates,
) {
  if (tracks.isEmpty) return null;
  final albumId = tracks.first.albumId;
  if (albumId != null && albumDates[albumId] != null) {
    return albumDates[albumId];
  }
  DateTime? earliest;
  for (final track in tracks) {
    final date = track.premiereDate;
    if (date == null) continue;
    if (earliest == null || date.isBefore(earliest)) earliest = date;
  }
  return earliest;
}

String _collectionMetadata(
  CollectionKind kind,
  List<Track> tracks,
  Map<String, DateTime> albumDates,
) {
  final segments = <String>[];
  if (kind == CollectionKind.album) {
    final artist = _albumArtist(tracks);
    if (artist != null) segments.add(artist);
    final date = _albumReleaseDate(tracks, albumDates);
    if (date != null) segments.add('${date.year}');
  }
  segments.add('${tracks.length} ${tracks.length == 1 ? 'song' : 'songs'}');
  final duration = _collectionDuration(tracks);
  if (duration != null) segments.add(_formatCollectionDuration(duration));
  return segments.join(' • ');
}

class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({required this.playlistId, super.key});

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      StreamBuilder<List<Playlist>>(
        stream: ref.watch(playlistsStreamProvider),
        builder: (context, playlistSnapshot) {
          final playlist = playlistSnapshot.data?.firstWhereOrNull(
            (item) => item.id == playlistId,
          );
          if (playlist == null) {
            return const Scaffold(
              body: SpotifinEmptyState(
                icon: Icons.queue_music_rounded,
                title: 'Playlist unavailable',
              ),
            );
          }
          return StreamBuilder<List<Track>>(
            stream: ref.watch(allTracksStreamProvider),
            builder: (context, trackSnapshot) {
              final byId = {
                for (final track in trackSnapshot.data ?? const <Track>[])
                  track.id: track,
              };
              final tracks = tracksInPlaylist(playlist, byId);
              return CollectionScreen(
                title: playlist.name,
                tracks: tracks,
                kind: CollectionKind.playlist,
                artwork: PlaylistArtwork(
                  tracks: tracks,
                  size: 160,
                  borderRadius: SpotifinRadii.card,
                ),
              );
            },
          );
        },
      );
}

class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({
    required this.title,
    required this.tracks,
    required this.kind,
    this.artwork,
    super.key,
  });
  final String title;
  final List<Track> tracks;
  final CollectionKind kind;
  final Widget? artwork;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumStableId = kind == CollectionKind.album && tracks.isNotEmpty
        ? tracks.first.albumId
        : null;
    final trackSort = ref.watch(collectionTrackSortProvider);
    final sortedTracks = sortTracks(tracks, trackSort);
    final sortControl = SortByDropdown<TrackSort>(
      value: trackSort,
      values: TrackSort.values,
      labelOf: (option) => option.label,
      tooltip: 'Sort collection songs',
      onChanged: (option) {
        if (option != null) {
          ref.read(collectionTrackSortProvider.notifier).set(option);
        }
      },
    );
    final header = _CollectionHeader(
      title: title,
      tracks: tracks,
      kind: kind,
      artwork: artwork,
      coverflowToggle: kind.hasArtistTabs
          ? CoverflowHeaderToggle(
              viewIds: [
                collectionCoverflowViewId('artist-songs', title, null),
                collectionCoverflowViewId('artist-albums', title, null),
              ],
            )
          : CoverflowHeaderToggle(
              viewIds: [
                collectionCoverflowViewId(kind.name, title, albumStableId),
              ],
            ),
    );
    if (!kind.hasArtistTabs) {
      final viewId = collectionCoverflowViewId(kind.name, title, albumStableId);
      final coverflow = ref.watch(coverflowModeProvider(viewId));
      final playback = ref.watch(playbackProvider);
      final items = trackCoverflowItems(sortedTracks);
      return MobileCoverflowScope(
        viewId: viewId,
        collection: MobileCoverflowCollection(
          items: items,
          contextTracks: sortedTracks,
          playback: MobileCoverflowPlayback.tracks,
        ),
        child: Scaffold(
          appBar: AppBar(
            title: Text(title),
            backgroundColor: Colors.transparent,
            actions: [CoverflowToggleButton(viewId: viewId)],
          ),
          body: coverflow
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: ListenableBuilder(
                      listenable: playback,
                      builder: (context, _) => CoverflowStage(
                        items: items,
                        initialIndex: ref.watch(
                          coverflowPositionProvider(viewId),
                        ),
                        currentTrackId: playback.currentTrack?.id,
                        playing: playback.playing,
                        onFocus: (index) => ref
                            .read(coverflowPositionProvider(viewId).notifier)
                            .set(index),
                        onCenterTap: (item) {
                          if (playback.currentTrack?.id ==
                              item.tracks.single.id) {
                            playback.toggle();
                          } else {
                            playback.playTrack(
                              item.tracks.single,
                              sortedTracks,
                            );
                          }
                        },
                      ),
                    ),
                  ),
                )
              : CoverflowScrollTracker(
                  viewId: viewId,
                  itemCount: items.length,
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(child: header),
                      SliverToBoxAdapter(child: sortControl),
                      SliverList.builder(
                        itemCount: sortedTracks.length,
                        itemBuilder: (context, index) => TrackTile(
                          track: sortedTracks[index],
                          contextTracks: sortedTracks,
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: SpotifinChromeInsets.bottomOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(title), backgroundColor: Colors.transparent),
      body: DefaultTabController(
        length: 2,
        child: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(child: header),
            const SliverPersistentHeader(
              pinned: true,
              delegate: _PinnedTabBar(
                SpotifinTabBar(labels: ['Songs', 'Albums']),
              ),
            ),
          ],
          body: TabBarView(
            children: [
              MobileCoverflowScope(
                viewId: collectionCoverflowViewId('artist-songs', title, null),
                tabIndex: 0,
                collection: MobileCoverflowCollection(
                  items: trackCoverflowItems(sortedTracks),
                  contextTracks: sortedTracks,
                  playback: MobileCoverflowPlayback.tracks,
                ),
                child: CoverflowSection(
                  viewId: collectionCoverflowViewId(
                    'artist-songs',
                    title,
                    null,
                  ),
                  items: trackCoverflowItems(sortedTracks),
                  onCenterTap: (item) => ref
                      .read(playbackProvider)
                      .playTrack(item.tracks.single, sortedTracks),
                  list: Column(
                    children: [
                      sortControl,
                      Expanded(
                        child: ListView.builder(
                          key: const PageStorageKey('artist-songs'),
                          padding: EdgeInsets.only(
                            bottom: SpotifinChromeInsets.bottomOf(context),
                          ),
                          itemCount: sortedTracks.length,
                          itemBuilder: (context, index) => TrackTile(
                            track: sortedTracks[index],
                            contextTracks: sortedTracks,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _ArtistAlbumsTab(
                key: const PageStorageKey('artist-albums'),
                tracks: tracks,
                viewId: collectionCoverflowViewId('artist-albums', title, null),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinnedTabBar extends SliverPersistentHeaderDelegate {
  const _PinnedTabBar(this.tabBar);

  final SpotifinTabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => ColoredBox(color: SpotifinColors.background, child: tabBar);

  @override
  bool shouldRebuild(_PinnedTabBar oldDelegate) =>
      oldDelegate.tabBar.labels != tabBar.labels;
}

class _CollectionHeader extends ConsumerWidget {
  const _CollectionHeader({
    required this.title,
    required this.tracks,
    required this.kind,
    this.artwork,
    this.coverflowToggle,
  });
  final String title;
  final List<Track> tracks;
  final CollectionKind kind;
  final Widget? artwork;
  final Widget? coverflowToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackProvider);
    return StreamBuilder<Map<String, DateTime>>(
      stream: ref.watch(albumDatesStreamProvider),
      initialData: const {},
      builder: (context, snapshot) => ListenableBuilder(
        listenable: playback,
        builder: (context, _) =>
            _content(context, playback, snapshot.data ?? const {}),
      ),
    );
  }

  Widget _headerArtwork() {
    if (artwork != null) return artwork!;
    if (tracks.isNotEmpty &&
        (kind == CollectionKind.album || kind == CollectionKind.artist)) {
      final first = tracks.first;
      return Artwork(
        itemId: first.albumId ?? first.id,
        size: 160,
        borderRadius: SpotifinRadii.card,
      );
    }
    return Icon(kind.fallbackIcon, size: 72, color: SpotifinColors.textMuted);
  }

  Widget _content(
    BuildContext context,
    PlaybackService playback,
    Map<String, DateTime> albumDates,
  ) {
    final metadata = _collectionMetadata(kind, tracks, albumDates);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [SpotifinColors.raised, SpotifinColors.background],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SpotifinSpacing.xl),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: SpotifinSpacing.lg,
          runSpacing: SpotifinSpacing.lg,
          children: [
            Container(
              width: 160,
              height: 160,
              decoration: const BoxDecoration(
                color: SpotifinColors.interactive,
                borderRadius: BorderRadius.all(
                  Radius.circular(SpotifinRadii.card),
                ),
                boxShadow: [SpotifinShadows.dialog],
              ),
              clipBehavior: Clip.antiAlias,
              child: _headerArtwork(),
            ),
            SizedBox(
              width: 320,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kind.label,
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: SpotifinColors.textMuted),
                  ),
                  const SizedBox(height: SpotifinSpacing.xs),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  if (metadata.isNotEmpty) ...[
                    const SizedBox(height: SpotifinSpacing.xs),
                    Text(
                      metadata,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: SpotifinSpacing.md),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: SpotifinSpacing.sm,
                    runSpacing: SpotifinSpacing.sm,
                    children: [
                      SpotifinPlayButton(
                        onPressed: tracks.isEmpty
                            ? null
                            : () =>
                                  playback.replaceQueue(tracks, shuffle: false),
                      ),
                      IconButton(
                        tooltip: 'Shuffle',
                        color: playback.shuffle
                            ? SpotifinColors.accent
                            : SpotifinColors.textMuted,
                        onPressed: tracks.isEmpty
                            ? null
                            : () =>
                                  playback.replaceQueue(tracks, shuffle: true),
                        icon: const Icon(Icons.shuffle_rounded),
                      ),
                      CollectionDownloadButton(tracks: tracks),
                      ?coverflowToggle,
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
