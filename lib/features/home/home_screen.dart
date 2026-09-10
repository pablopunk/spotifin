import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../storage/database.dart';
import '../../services/mixes/mix_generator.dart';
import '../common/artwork.dart';
import '../common/design_system.dart';
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
                SliverAppBar(
                  expandedHeight: 112,
                  pinned: true,
                  flexibleSpace: const FlexibleSpaceBar(
                    titlePadding: EdgeInsets.fromLTRB(20, 0, 20, 18),
                    title: Text('Good listening'),
                  ),
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
                if (recent.any((track) => track.lastPlayed != null))
                  SliverToBoxAdapter(
                    child: _HorizontalSection(
                      title: 'Recently played',
                      tracks: recent
                          .where((track) => track.lastPlayed != null)
                          .take(12)
                          .toList(),
                      contextTracks: recent,
                    ),
                  ),
                SliverToBoxAdapter(
                  child: _HorizontalSection(
                    title: 'Recently added',
                    tracks: added.take(12).toList(),
                    contextTracks: added,
                  ),
                ),
                if (favorites.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _HorizontalSection(
                      title: 'Favorites',
                      tracks: favorites.take(12).toList(),
                      contextTracks: favorites,
                    ),
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
                const SliverToBoxAdapter(child: SpotifinPageTitle('All songs')),
                SliverList.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, index) =>
                      TrackTile(track: tracks[index], contextTracks: tracks),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
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
    padding: const EdgeInsets.only(bottom: SpotifinSpacing.xl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SpotifinSpacing.lg),
          child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
        ),
        const SizedBox(height: SpotifinSpacing.sm),
        SizedBox(
          height: 224,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: SpotifinSpacing.lg),
            scrollDirection: Axis.horizontal,
            itemCount: tracks.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: SpotifinSpacing.md),
            itemBuilder: (context, index) {
              final track = tracks[index];
              return SizedBox(
                width: 164,
                child: Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(SpotifinRadii.card),
                    onTap: () =>
                        ProviderScope.containerOf(context)
                            .read(playbackProvider)
                            .playTrack(track, contextTracks),
                    child: Padding(
                      padding: const EdgeInsets.all(SpotifinSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Artwork(
                            itemId: track.id,
                            size: 140,
                            borderRadius: SpotifinRadii.small,
                          ),
                          const SizedBox(height: SpotifinSpacing.sm),
                          Text(
                            track.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
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
  Widget build(BuildContext context) => const SpotifinEmptyState(
    icon: Icons.library_music_outlined,
    title: 'No music found',
    message: 'Check that this Jellyfin account can access a music library.',
  );
}
