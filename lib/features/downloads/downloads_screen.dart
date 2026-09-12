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
  Widget build(BuildContext context, WidgetRef ref) {
    final desktop =
        MediaQuery.sizeOf(context).width >= SpotifinBreakpoints.rail;
    return Scaffold(
      appBar: desktop
          ? null
          : AppBar(
              title: const Text('Downloads'),
              actions: [_ClearDownloadsButton(compact: true)],
            ),
      body: StreamBuilder<List<Track>>(
        stream: ref.watch(tracksByDateAddedStreamProvider),
        builder: (context, trackSnapshot) => StreamBuilder<List<Download>>(
          stream: ref.watch(downloadsStreamProvider),
          builder: (context, downloadSnapshot) {
            final tracks = trackSnapshot.data ?? const [];
            final downloads = downloadSnapshot.data ?? const [];
            if (downloads.isEmpty) return const _EmptyDownloads();
            final byDownloadId = {
              for (final download in downloads) download.trackId: download,
            };
            final orderedTracks = tracks
                .where((track) => byDownloadId.containsKey(track.id))
                .toList(growable: false);
            final completeTracks = orderedTracks
                .where((track) => byDownloadId[track.id]?.status == 'complete')
                .toList(growable: false);
            return ListView.builder(
              padding: EdgeInsets.only(
                bottom: SpotifinChromeInsets.bottomOf(context),
              ),
              itemCount: orderedTracks.length + (desktop ? 1 : 0),
              itemBuilder: (context, index) {
                if (desktop && index == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(
                      SpotifinSpacing.lg,
                      SpotifinSpacing.lg,
                      SpotifinSpacing.md,
                      SpotifinSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Downloads',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const Spacer(),
                        const _ClearDownloadsButton(),
                      ],
                    ),
                  );
                }
                final track = orderedTracks[index - (desktop ? 1 : 0)];
                final download = byDownloadId[track.id]!;
                if (download.status == 'complete') {
                  return Dismissible(
                    key: ValueKey(track.id),
                    background: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: SpotifinSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: SpotifinColors.negative.withValues(alpha: .24),
                        borderRadius: BorderRadius.circular(
                          SpotifinRadii.small,
                        ),
                      ),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      child: const Icon(Icons.delete_outline_rounded),
                    ),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) => _confirmRemove(context, track),
                    onDismissed: (_) =>
                        ref.read(downloadProvider).remove(track.id),
                    child: TrackTile(
                      track: track,
                      contextTracks: completeTracks,
                    ),
                  );
                }
                return ListTile(
                  leading: download.status == 'failed'
                      ? const Icon(Icons.error_outline_rounded)
                      : const CircularProgressIndicator(),
                  title: Text(track.name),
                  subtitle: Text(download.error ?? download.status),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (download.status == 'failed')
                        IconButton(
                          tooltip: 'Retry',
                          onPressed: () {
                            final app = ref.read(appControllerProvider);
                            if (app.session != null) {
                              ref
                                  .read(downloadProvider)
                                  .download(
                                    app.session!,
                                    track,
                                    small: app.smallDownloads,
                                  );
                            }
                          },
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      IconButton(
                        tooltip: 'Remove download',
                        onPressed: () async {
                          if (await _confirmRemove(context, track)) {
                            await ref.read(downloadProvider).remove(track.id);
                          }
                        },
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ClearDownloadsButton extends ConsumerWidget {
  const _ClearDownloadsButton({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) => compact
      ? IconButton(
          tooltip: 'Remove all downloads',
          onPressed: () => _clear(context, ref),
          icon: const Icon(Icons.delete_sweep_outlined),
        )
      : OutlinedButton.icon(
          onPressed: () => _clear(context, ref),
          icon: const Icon(Icons.delete_sweep_outlined),
          label: const Text('Remove all'),
        );

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove all downloads?'),
        content: const Text(
          'All offline songs will be removed from this device. They will '
          'stay in your Jellyfin library.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: SpotifinColors.negative,
              foregroundColor: SpotifinColors.voidBlack,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove all'),
          ),
        ],
      ),
    );
    if (confirmed == true) await ref.read(downloadProvider).clear();
  }
}

Future<bool> _confirmRemove(BuildContext context, Track track) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove download?'),
        content: Text(
          '“${track.name}” will be removed from this device. It will stay in '
          'your Jellyfin library.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    ) ??
    false;

class _EmptyDownloads extends StatelessWidget {
  const _EmptyDownloads();

  @override
  Widget build(BuildContext context) => const SpotifinEmptyState(
    icon: Icons.download_for_offline_outlined,
    title: 'No downloads yet',
    message: 'Your offline music will appear here.',
  );
}
