import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../storage/database.dart';
import '../../services/mixes/mix_generator.dart';
import '../common/artwork.dart';
import '../common/track_tile.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      StreamBuilder<List<Track>>(
        stream: ref.watch(databaseProvider).watchTracks(),
        builder: (context, snapshot) {
          final tracks = snapshot.data ?? const [];
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (tracks.isEmpty) return const _EmptyCatalog();
          final recent = [...tracks]
            ..sort(
              (a, b) => (b.lastPlayed ?? DateTime(0)).compareTo(
                a.lastPlayed ?? DateTime(0),
              ),
            );
          final added = [...tracks]
            ..sort(
              (a, b) => (b.dateCreated ?? DateTime(0)).compareTo(
                a.dateCreated ?? DateTime(0),
              ),
            );
          final favorites = tracks.where((track) => track.favorite).toList();
          final mixes = const MixGenerator().generate(tracks, DateTime.now());
          return RefreshIndicator(
            onRefresh: ref.read(appControllerProvider.notifier).refresh,
            child: CustomScrollView(
              slivers: [
                SliverAppBar.large(
                  title: const Text('Good listening'),
                  backgroundColor: SpotifinColors.background,
                  actions: [
                    IconButton(
                      tooltip: 'Refresh library',
                      onPressed: ref.watch(appControllerProvider).syncing
                          ? null
                          : ref.read(appControllerProvider.notifier).refresh,
                      icon: ref.watch(appControllerProvider).syncing
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
                SliverList.list(
                  children: [
                    if (recent.any((track) => track.lastPlayed != null))
                      _HorizontalSection(
                        title: 'Recently played',
                        tracks: recent
                            .where((track) => track.lastPlayed != null)
                            .take(12)
                            .toList(),
                        contextTracks: recent,
                      ),
                    _HorizontalSection(
                      title: 'Recently added',
                      tracks: added.take(12).toList(),
                      contextTracks: added,
                    ),
                    if (favorites.isNotEmpty)
                      _HorizontalSection(
                        title: 'Favorites',
                        tracks: favorites.take(12).toList(),
                        contextTracks: favorites,
                      ),
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'All songs',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...tracks
                        .take(20)
                        .map(
                          (track) =>
                              TrackTile(track: track, contextTracks: tracks),
                        ),
                    const SizedBox(height: 120),
                  ],
                ),
                ...mixes
                    .take(3)
                    .map(
                      (mix) => SliverToBoxAdapter(
                        child: _HorizontalSection(
                          title: mix.name,
                          tracks: mix.tracks.take(12).toList(),
                          contextTracks: mix.tracks,
                        ),
                      ),
                    ),
              ],
            ),
          );
        },
      );
}

class _HorizontalSection extends StatelessWidget {
  const _HorizontalSection({
    required this.title,
    required this.tracks,
    required this.contextTracks,
  });
  final String title;
  final List<Track> tracks;
  final List<Track> contextTracks;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 205,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: tracks.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final track = tracks[index];
              return SizedBox(
                width: 142,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () =>
                      ProviderScope.containerOf(context)
                          .read(playbackProvider)
                          .playTrack(track, contextTracks),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Artwork(itemId: track.id, size: 142, borderRadius: 14),
                      const SizedBox(height: 8),
                      Text(
                        track.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: Colors.white60),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _EmptyCatalog extends StatelessWidget {
  const _EmptyCatalog();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.library_music_outlined, size: 64, color: Colors.white38),
          SizedBox(height: 16),
          Text('No music found'),
          SizedBox(height: 6),
          Text('Check that this Jellyfin account can access a music library.'),
        ],
      ),
    ),
  );
}
