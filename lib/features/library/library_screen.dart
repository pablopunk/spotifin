import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../storage/database.dart';
import '../common/artwork.dart';
import '../common/track_tile.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => DefaultTabController(
    length: 4,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Your library'),
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
                groups: groupBy(
                  tracks.where((track) => track.album.isNotEmpty),
                  (Track track) => track.album,
                ),
                icon: Icons.album_rounded,
              ),
              _GroupedList(
                groups: groupBy(tracks, (Track track) => track.artist),
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
  const _GroupedList({required this.groups, required this.icon});
  final Map<String, List<Track>> groups;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final entries = groups.entries.sortedBy((entry) => entry.key.toLowerCase());
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final first = entry.value.first;
        return ListTile(
          leading: Artwork(
            itemId: first.albumId ?? first.id,
            size: 58,
            borderRadius: icon == Icons.person_rounded ? 29 : 10,
          ),
          title: Text(entry.key),
          subtitle: Text('${entry.value.length} songs'),
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
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 120),
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              final ids = (jsonDecode(playlist.trackIds) as List<dynamic>)
                  .cast<String>();
              final playlistTracks = ids
                  .map((id) => byId[id])
                  .whereType<Track>()
                  .toList();
              return ListTile(
                leading: Artwork(itemId: playlist.id, size: 58),
                title: Text(playlist.name),
                subtitle: Text('${playlistTracks.length} songs'),
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
    appBar: AppBar(title: Text(title)),
    body: CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(icon, size: 54),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    '$title\n${tracks.length} songs',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: tracks.isEmpty
                      ? null
                      : () => ref.read(playbackProvider).replaceQueue(tracks),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play'),
                ),
              ],
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
