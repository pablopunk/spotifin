import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../storage/database.dart';
import '../common/artwork.dart';
import '../common/design_system.dart';
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
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Songs'),
              Tab(text: 'Albums'),
              Tab(text: 'Artists'),
              Tab(text: 'Playlists'),
            ],
          ),
        ),
        body: StreamBuilder<List<Track>>(
          stream: ref.watch(databaseProvider).watchTracks(),
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
    padding: const EdgeInsets.only(bottom: 120),
    itemCount: tracks.length,
    itemBuilder: (context, index) =>
        TrackTile(track: tracks[index], contextTracks: tracks),
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
        return SpotifinCollectionCard(
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
              builder: (_) => _CollectionScreen(
                title: entry.key,
                tracks: entry.value,
                icon: icon,
              ),
            ),
          ),
        );
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
              final ids = (jsonDecode(playlist.trackIds) as List<dynamic>)
                  .cast<String>();
              final playlistTracks = ids
                  .map((id) => byId[id])
                  .whereType<Track>()
                  .toList();
              return SpotifinCollectionCard(
                artwork: LayoutBuilder(
                  builder: (context, constraints) => Artwork(
                    itemId: playlist.id,
                    size: constraints.biggest.shortestSide,
                    borderRadius: SpotifinRadii.small,
                  ),
                ),
                title: playlist.name,
                subtitle: '${playlistTracks.length} songs',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _CollectionScreen(
                      title: playlist.name,
                      tracks: playlistTracks,
                      icon: Icons.queue_music_rounded,
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
}

class _CollectionScreen extends ConsumerWidget {
  const _CollectionScreen({
    required this.title,
    required this.tracks,
    required this.icon,
  });
  final String title;
  final List<Track> tracks;
  final IconData icon;

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
                    child: Icon(
                      icon,
                      size: 72,
                      color: SpotifinColors.textMuted,
                    ),
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
                        const SizedBox(height: SpotifinSpacing.xs),
                        SpotifinCountLabel(tracks.length),
                      ],
                    ),
                  ),
                  SpotifinPlayButton(
                    onPressed: tracks.isEmpty
                        ? null
                        : () => ref.read(playbackProvider).replaceQueue(tracks),
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
