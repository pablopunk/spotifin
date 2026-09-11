import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../services/downtify/downtify_models.dart';
import '../../storage/database.dart';
import '../common/design_system.dart';

class ExternalTrackTile extends ConsumerWidget {
  const ExternalTrackTile({required this.song, super.key});

  final DowntifySong song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(downtifyControllerProvider);
    final item = ref
        .read(downtifyControllerProvider.notifier)
        .importFor(song.id);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SpotifinSpacing.sm),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(SpotifinRadii.small),
        child: ListTile(
          minTileHeight: 64,
          contentPadding: const EdgeInsets.only(
            left: SpotifinSpacing.xs,
            right: SpotifinSpacing.sm,
          ),
          leading: _ExternalArtwork(song: song, item: item),
          title: Text(
            song.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          subtitle: Text(
            [
              song.artist,
              if (song.albumName.isNotEmpty) song.albumName,
              if (song.duration != null) _duration(song.duration!),
            ].join(' • '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: _ImportAction(song: song, item: item),
          onTap: () async {
            if (!await launchUrl(
              song.sourceUri,
              mode: LaunchMode.externalApplication,
            )) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not open YouTube.')),
              );
            }
          },
        ),
      ),
    );
  }
}

class _ExternalArtwork extends StatelessWidget {
  const _ExternalArtwork({required this.song, required this.item});

  final DowntifySong song;
  final DowntifyImport? item;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(SpotifinRadii.small),
        child: SizedBox.square(
          dimension: 48,
          child: song.coverUri == null
              ? const ColoredBox(
                  color: SpotifinColors.raised,
                  child: Icon(Icons.music_note_rounded),
                )
              : Image.network(
                  song.coverUri.toString(),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: SpotifinColors.raised,
                    child: Icon(Icons.music_note_rounded),
                  ),
                ),
        ),
      ),
      Positioned(
        right: -5,
        bottom: -5,
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: SpotifinColors.raised,
            shape: BoxShape.circle,
            border: Border.all(color: SpotifinColors.background, width: 2),
          ),
          child: Icon(
            _statusIcon(item),
            size: 14,
            color: SpotifinColors.accent,
          ),
        ),
      ),
    ],
  );
}

class _ImportAction extends ConsumerWidget {
  const _ImportAction({required this.song, required this.item});

  final DowntifySong song;
  final DowntifyImport? item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (item?.status == 'imported') {
      return const IconButton(
        tooltip: 'Available in Jellyfin',
        onPressed: null,
        icon: Icon(Icons.check_circle_rounded),
      );
    }
    final active =
        item != null &&
        const {
          'submitting',
          'queued',
          'downloading',
          'requestingScan',
          'waitingForJellyfin',
          'scanDenied',
        }.contains(item!.status);
    if (active) {
      return SizedBox.square(
        dimension: 38,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            value: item!.status == 'downloading' && item!.progress > 0
                ? item!.progress / 100
                : null,
          ),
        ),
      );
    }
    final failed =
        item != null &&
        const {'downloadFailed', 'importTimedOut'}.contains(item!.status);
    return IconButton(
      tooltip: failed ? 'Retry server import' : 'Add to Jellyfin library',
      onPressed: () => failed
          ? ref.read(downtifyControllerProvider.notifier).retry(item!)
          : ref.read(downtifyControllerProvider.notifier).enqueue(song),
      icon: Icon(
        failed ? Icons.refresh_rounded : Icons.cloud_download_outlined,
      ),
    );
  }
}

IconData _statusIcon(DowntifyImport? item) => switch (item?.status) {
  'imported' => Icons.check_rounded,
  'downloadFailed' || 'importTimedOut' => Icons.error_outline_rounded,
  'submitting' || 'queued' || 'downloading' => Icons.downloading_rounded,
  'requestingScan' ||
  'waitingForJellyfin' ||
  'scanDenied' => Icons.sync_rounded,
  _ => Icons.cloud_download_outlined,
};

String _duration(Duration value) {
  final minutes = value.inMinutes;
  final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
