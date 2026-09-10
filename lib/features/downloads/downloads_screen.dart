import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../storage/database.dart';
import '../common/design_system.dart';
import '../common/track_tile.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Downloads')),
    body: StreamBuilder<List<Track>>(
      stream: ref.watch(databaseProvider).watchTracks(),
      builder: (context, trackSnapshot) => StreamBuilder<List<Download>>(
        stream: ref.watch(databaseProvider).watchDownloads(),
        builder: (context, downloadSnapshot) {
          final tracks = trackSnapshot.data ?? const [];
          final byId = {for (final track in tracks) track.id: track};
          final downloads = downloadSnapshot.data ?? const [];
          if (downloads.isEmpty) return const _EmptyDownloads();
          final completeTracks = downloads
              .where((download) => download.status == 'complete')
              .map((download) => byId[download.trackId])
              .whereType<Track>()
              .toList();
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 120),
            itemCount: downloads.length,
            itemBuilder: (context, index) {
              final download = downloads[index];
              final track = byId[download.trackId];
              if (track == null) return const SizedBox.shrink();
              if (download.status == 'complete') {
                return Dismissible(
                  key: ValueKey(track.id),
                  background: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: SpotifinSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: SpotifinColors.negative.withValues(alpha: .24),
                      borderRadius: BorderRadius.circular(SpotifinRadii.small),
                    ),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    child: const Icon(Icons.delete_outline_rounded),
                  ),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) =>
                      ref.read(downloadProvider).remove(track.id),
                  child: TrackTile(track: track, contextTracks: completeTracks),
                );
              }
              return ListTile(
                leading: download.status == 'failed'
                    ? const Icon(Icons.error_outline_rounded)
                    : const CircularProgressIndicator(),
                title: Text(track.name),
                subtitle: Text(download.error ?? download.status),
                trailing: download.status == 'failed'
                    ? IconButton(
                        tooltip: 'Retry',
                        onPressed: () {
                          final session = ref
                              .read(appControllerProvider)
                              .session;
                          if (session != null) {
                            ref
                                .read(downloadProvider)
                                .download(
                                  session,
                                  track,
                                  small: ref
                                      .read(appControllerProvider)
                                      .smallDownloads,
                                );
                          }
                        },
                        icon: const Icon(Icons.refresh_rounded),
                      )
                    : null,
              );
            },
          );
        },
      ),
    ),
  );
}

class _EmptyDownloads extends StatelessWidget {
  const _EmptyDownloads();

  @override
  Widget build(BuildContext context) => const SpotifinEmptyState(
    icon: Icons.download_for_offline_outlined,
    title: 'No downloads yet',
    message: 'Your offline music will appear here.',
  );
}
