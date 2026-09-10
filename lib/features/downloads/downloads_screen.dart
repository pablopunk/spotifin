import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../storage/database.dart';
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
                    color: Theme.of(context).colorScheme.errorContainer,
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
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.download_for_offline_outlined,
            size: 68,
            color: Colors.white38,
          ),
          SizedBox(height: 18),
          Text('Your offline music will appear here.'),
        ],
      ),
    ),
  );
}
