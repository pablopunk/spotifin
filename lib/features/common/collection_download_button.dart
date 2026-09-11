import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../storage/database.dart';

class CollectionDownloadButton extends ConsumerWidget {
  const CollectionDownloadButton({required this.tracks, super.key});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statuses = ref.watch(downloadStatusesProvider).value ?? const {};
    final complete = tracks
        .where((track) => statuses[track.id] == 'complete')
        .length;
    final running = tracks.any(
      (track) => const {'queued', 'downloading'}.contains(statuses[track.id]),
    );
    final allDownloaded = tracks.isNotEmpty && complete == tracks.length;
    return OutlinedButton.icon(
      onPressed: tracks.isEmpty || allDownloaded || running
          ? null
          : () => _download(context, ref),
      icon: running
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(
              allDownloaded
                  ? Icons.download_done_rounded
                  : Icons.download_rounded,
            ),
      label: Text(_label(complete, running, allDownloaded)),
    );
  }

  String _label(int complete, bool running, bool allDownloaded) {
    if (allDownloaded) return 'Downloaded';
    if (running) return '$complete / ${tracks.length}';
    if (complete > 0) return 'Download remaining';
    return 'Download all';
  }

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    final app = ref.read(appControllerProvider);
    if (app.session == null) return;
    await ref
        .read(downloadProvider)
        .downloadAll(app.session!, tracks, small: app.smallDownloads);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${tracks.length} songs added to downloads.')),
    );
  }
}
