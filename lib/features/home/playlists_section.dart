import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../storage/database.dart';
import '../common/design_system.dart';
import '../common/playlist_artwork.dart';
import '../common/playlist_context_menu.dart';
import '../library/library_screen.dart';

class PlaylistsSection extends ConsumerWidget {
  const PlaylistsSection({
    required this.tracks,
    this.onOpenPlaylists,
    super.key,
  });

  final List<Track> tracks;
  final VoidCallback? onOpenPlaylists;

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
                  child: InkWell(
                    borderRadius: BorderRadius.circular(SpotifinRadii.small),
                    onTap: () {
                      if (onOpenPlaylists != null) {
                        onOpenPlaylists!();
                        return;
                      }
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              const LibraryScreen(initialTabIndex: 3),
                        ),
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'Playlists',
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 28,
                          color: SpotifinColors.textMuted,
                        ),
                      ],
                    ),
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

class _PlaylistCard extends ConsumerWidget {
  const _PlaylistCard({required this.playlist, required this.tracksById});

  final Playlist playlist;
  final Map<String, Track> tracksById;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = tracksInPlaylist(playlist, tracksById);
    return PlaylistContextMenu(
      playlist: playlist,
      tracks: tracks,
      child: SizedBox(
        width: 164,
        child: SpotifinCollectionCard(
          artwork: PlaylistArtwork(tracks: tracks, size: 140),
          title: playlist.name,
          subtitle: '${tracks.length} songs',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PlaylistScreen(playlistId: playlist.id),
            ),
          ),
          onPlay: tracks.isEmpty
              ? null
              : () => ref.read(playbackProvider).replaceQueue(tracks),
        ),
      ),
    );
  }
}
