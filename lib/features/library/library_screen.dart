import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../services/albums/album_type_service.dart';
import '../../storage/database.dart';
import '../common/artwork.dart';
import '../common/album_context_menu.dart';
import '../common/collection_download_button.dart';
import '../common/design_system.dart';
import '../common/playlist_artwork.dart';
import '../common/track_tile.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final desktop =
        MediaQuery.sizeOf(context).width >= SpotifinBreakpoints.rail;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: desktop ? null : const Text('Your library'),
          toolbarHeight: desktop ? 0 : kToolbarHeight,
          bottom: const SpotifinTabBar(
            labels: ['Songs', 'Albums', 'Artists', 'Playlists'],
          ),
        ),
        body: StreamBuilder<List<Track>>(
          stream: ref.watch(databaseProvider).watchTracksByDateAdded(),
          builder: (context, trackSnapshot) {
            final tracks = trackSnapshot.data ?? const [];
            return TabBarView(
              children: [
                _TrackList(tracks: tracks),
                _GroupedList(
                  tracks: tracks,
                  groupName: _albumName,
                  icon: Icons.album_rounded,
                ),
                _GroupedList(
                  tracks: tracks,
                  groupName: _artistName,
                  icon: Icons.person_rounded,
                  artist: true,
                ),
                _PlaylistsTab(tracks: tracks),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TrackList extends StatelessWidget {
  const _TrackList({required this.tracks});
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: EdgeInsets.only(bottom: SpotifinChromeInsets.bottomOf(context)),
    itemCount: tracks.length + 1,
    itemBuilder: (context, index) {
      if (index == 0) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            SpotifinSpacing.md,
            SpotifinSpacing.md,
            SpotifinSpacing.md,
            SpotifinSpacing.sm,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: CollectionDownloadButton(tracks: tracks),
          ),
        );
      }
      return TrackTile(track: tracks[index - 1], contextTracks: tracks);
    },
  );
}

class _GroupedList extends StatelessWidget {
  const _GroupedList({
    required this.tracks,
    required this.groupName,
    required this.icon,
    this.artist = false,
  });
  final List<Track> tracks;
  final String Function(Track) groupName;
  final IconData icon;
  final bool artist;

  @override
  Widget build(BuildContext context) {
    final groups = groupBy(
      tracks.where((track) => groupName(track).isNotEmpty),
      groupName,
    );
    final entries = groups.entries.sortedBy((entry) => entry.key.toLowerCase());
    if (entries.isEmpty) {
      return const SpotifinEmptyState(
        icon: Icons.library_music_outlined,
        title: 'Nothing here yet',
      );
    }
    return spotifinGrid(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _CollectionCard(
          title: entry.key,
          tracks: entry.value,
          artist: artist,
          menu: !artist,
        );
      },
    );
  }
}

class _CollectionCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
            icon: artist ? Icons.person_rounded : Icons.album_rounded,
            artist: artist,
          ),
        ),
      ),
    );
    if (!menu) return card;
    return AlbumContextMenu(title: title, tracks: tracks, child: card);
  }
}

class _ArtistAlbumsTab extends ConsumerStatefulWidget {
  const _ArtistAlbumsTab({required this.tracks, super.key});
  final List<Track> tracks;

  @override
  ConsumerState<_ArtistAlbumsTab> createState() => _ArtistAlbumsTabState();
}

class _ArtistAlbumsTabState extends ConsumerState<_ArtistAlbumsTab> {
  var _kinds = const <String, AlbumKind>{};

  @override
  void initState() {
    super.initState();
    unawaited(_resolve());
  }

  Future<void> _resolve() async {
    final albums = _albumGroups(widget.tracks);
    final session = ref.read(appControllerProvider).session;
    final kinds = await ref.read(albumTypeServiceProvider).resolve(session, [
      for (final album in albums) ?album.albumId,
    ]);
    if (!mounted) return;
    setState(() => _kinds = kinds);
  }

  @override
  Widget build(BuildContext context) {
    final albums = _albumGroups(widget.tracks);
    if (albums.isEmpty) {
      return const SpotifinEmptyState(
        icon: Icons.library_music_outlined,
        title: 'Nothing here yet',
      );
    }
    final singles = albums
        .where((album) => _isSingleOrEp(_kinds[album.albumId]))
        .toList();
    final full = albums
        .where((album) => !_isSingleOrEp(_kinds[album.albumId]))
        .toList();
    return CustomScrollView(
      slivers: [
        if (full.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SpotifinPageTitle('Albums')),
          _grid(full),
        ],
        if (singles.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SpotifinPageTitle('Singles & EPs')),
          _grid(singles),
        ],
        SliverToBoxAdapter(
          child: SizedBox(height: SpotifinChromeInsets.bottomOf(context)),
        ),
      ],
    );
  }

  Widget _grid(List<_AlbumGroup> albums) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: SpotifinSpacing.md),
    sliver: SliverGrid.builder(
      gridDelegate: spotifinGridDelegate,
      itemCount: albums.length,
      itemBuilder: (context, index) => _CollectionCard(
        title: albums[index].name,
        tracks: albums[index].tracks,
        menu: true,
      ),
    ),
  );
}

class _AlbumGroup {
  const _AlbumGroup({this.albumId, required this.name, required this.tracks});
  final String? albumId;
  final String name;
  final List<Track> tracks;
}

bool _isSingleOrEp(AlbumKind? kind) =>
    kind == AlbumKind.single || kind == AlbumKind.ep;

List<_AlbumGroup> _albumGroups(List<Track> tracks) {
  final grouped = <String, _AlbumGroup>{};
  for (final track in tracks) {
    if (track.album.isEmpty) continue;
    final key = track.albumId ?? track.album;
    grouped
        .putIfAbsent(
          key,
          () => _AlbumGroup(
            albumId: track.albumId,
            name: track.album,
            tracks: [],
          ),
        )
        .tracks
        .add(track);
  }
  return grouped.values.sortedBy((album) => album.name.toLowerCase()).toList();
}

String _albumName(Track track) => track.album;

String _artistName(Track track) => track.artist;

class _PlaylistsTab extends ConsumerWidget {
  const _PlaylistsTab({required this.tracks});
  final List<Track> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      StreamBuilder<List<Playlist>>(
        stream: ref.watch(databaseProvider).watchPlaylists(),
        builder: (context, snapshot) {
          final playlists = snapshot.data ?? const [];
          final byId = {for (final track in tracks) track.id: track};
          if (playlists.isEmpty) {
            return const SpotifinEmptyState(
              icon: Icons.queue_music_rounded,
              title: 'No playlists yet',
              message: 'Save your current queue to create one.',
            );
          }
          return spotifinGrid(
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              final playlistTracks = tracksInPlaylist(playlist, byId);
              return SpotifinCollectionCard(
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
                      icon: Icons.queue_music_rounded,
                      artwork: PlaylistArtwork(
                        tracks: playlistTracks,
                        size: 160,
                        borderRadius: SpotifinRadii.card,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
}

class PlaylistScreen extends ConsumerWidget {
  const PlaylistScreen({required this.playlistId, super.key});

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      StreamBuilder<List<Playlist>>(
        stream: ref.watch(databaseProvider).watchPlaylists(),
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
            stream: ref.watch(databaseProvider).watchTracks(),
            builder: (context, trackSnapshot) {
              final byId = {
                for (final track in trackSnapshot.data ?? const <Track>[])
                  track.id: track,
              };
              final tracks = tracksInPlaylist(playlist, byId);
              return CollectionScreen(
                title: playlist.name,
                tracks: tracks,
                icon: Icons.queue_music_rounded,
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
    required this.icon,
    this.artwork,
    this.artist = false,
    super.key,
  });
  final String title;
  final List<Track> tracks;
  final IconData icon;
  final Widget? artwork;
  final bool artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final header = _CollectionHeader(
      title: title,
      tracks: tracks,
      icon: icon,
      artwork: artwork,
    );
    return Scaffold(
      appBar: AppBar(title: Text(title), backgroundColor: Colors.transparent),
      body: artist
          ? DefaultTabController(
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
                    ListView.builder(
                      key: const PageStorageKey('artist-songs'),
                      padding: EdgeInsets.only(
                        bottom: SpotifinChromeInsets.bottomOf(context),
                      ),
                      itemCount: tracks.length,
                      itemBuilder: (context, index) => TrackTile(
                        track: tracks[index],
                        contextTracks: tracks,
                      ),
                    ),
                    _ArtistAlbumsTab(
                      key: const PageStorageKey('artist-albums'),
                      tracks: tracks,
                    ),
                  ],
                ),
              ),
            )
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: header),
                SliverList.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, index) =>
                      TrackTile(track: tracks[index], contextTracks: tracks),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 110)),
              ],
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
    required this.icon,
    this.artwork,
  });
  final String title;
  final List<Track> tracks;
  final IconData icon;
  final Widget? artwork;

  @override
  Widget build(BuildContext context, WidgetRef ref) => DecoratedBox(
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
            child:
                artwork ??
                Icon(icon, size: 72, color: SpotifinColors.textMuted),
          ),
          SizedBox(
            width: 320,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'COLLECTION',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: SpotifinSpacing.xs),
                Text(title, style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: SpotifinSpacing.md),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: SpotifinSpacing.sm,
                  runSpacing: SpotifinSpacing.sm,
                  children: [
                    SpotifinCountLabel(tracks.length),
                    SpotifinPlayButton(
                      onPressed: tracks.isEmpty
                          ? null
                          : () =>
                                ref.read(playbackProvider).replaceQueue(tracks),
                    ),
                    CollectionDownloadButton(tracks: tracks),
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
