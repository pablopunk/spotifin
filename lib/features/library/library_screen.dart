import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
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
  });
  final List<Track> tracks;
  final String Function(Track) groupName;
  final IconData icon;

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
        final first = entry.value.first;
        final card = SpotifinCollectionCard(
          artwork: LayoutBuilder(
            builder: (context, constraints) => Artwork(
              itemId: first.albumId ?? first.id,
              size: constraints.biggest.shortestSide,
              borderRadius: icon == Icons.person_rounded
                  ? constraints.biggest.shortestSide / 2
                  : SpotifinRadii.small,
            ),
          ),
          title: entry.key,
          subtitle: '${entry.value.length} songs',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CollectionScreen(
                title: entry.key,
                tracks: entry.value,
                icon: icon,
              ),
            ),
          ),
        );
        return icon == Icons.album_rounded
            ? AlbumContextMenu(
                title: entry.key,
                tracks: entry.value,
                child: card,
              )
            : card;
      },
    );
  }
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
    super.key,
  });
  final String title;
  final List<Track> tracks;
  final IconData icon;
  final Widget? artwork;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: Text(title), backgroundColor: Colors.transparent),
    body: CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: DecoratedBox(
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
                        Text(
                          title,
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
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
                                  : () => ref
                                        .read(playbackProvider)
                                        .replaceQueue(tracks),
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
          ),
        ),
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
