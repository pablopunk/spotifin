import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../storage/database.dart';
import '../common/design_system.dart';
import '../common/playlist_artwork.dart';
import '../library/library_screen.dart';

class PlaylistsSection extends ConsumerWidget {
  const PlaylistsSection({required this.tracks, super.key});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      StreamBuilder<List<Playlist>>(
        stream: ref.watch(playlistsStreamProvider),
        builder: (context, snapshot) {
          final playlists = snapshot.data ?? const <Playlist>[];
          if (playlists.isEmpty) return const SizedBox.shrink();
          final tracksById = {for (final track in tracks) track.id: track};
          return Padding(
            padding: const EdgeInsets.only(bottom: SpotifinSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SpotifinSpacing.lg,
                  ),
                  child: Text(
                    'Playlists',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: SpotifinSpacing.sm),
                SizedBox(
                  height: 224,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SpotifinSpacing.lg,
                    ),
                    scrollDirection: Axis.horizontal,
                    itemCount: playlists.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: SpotifinSpacing.md),
                    itemBuilder: (context, index) => _PlaylistCard(
                      playlist: playlists[index],
                      tracksById: tracksById,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.playlist, required this.tracksById});

  final Playlist playlist;
  final Map<String, Track> tracksById;

  @override
  Widget build(BuildContext context) {
    final tracks = tracksInPlaylist(playlist, tracksById);
    return SizedBox(
      width: 164,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(SpotifinRadii.card),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PlaylistScreen(playlistId: playlist.id),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(SpotifinSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PlaylistArtwork(tracks: tracks, size: 140),
                const SizedBox(height: SpotifinSpacing.sm),
                Text(
                  playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  '${tracks.length} songs',
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
  }
}
