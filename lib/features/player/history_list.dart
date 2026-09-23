import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../services/playback/recently_played.dart';
import '../../storage/database.dart';
import '../common/artwork.dart';
import '../common/design_system.dart';

/// History list backed by Jellyfin Recently Played.
///
/// Source of truth: Jellyfin's Recently Played data, read from the local
/// cache (`recentlyPlayedStreamProvider`, populated from
/// `UserData.LastPlayedDate` on every sync and refreshable via
/// `AppController.refreshHistory`). The transient session overlay
/// (`PlaybackService.history`) is merged on top with [mergeRecentlyPlayed] so
/// just-played tracks appear instantly, including offline.
///
/// Explicit fallback strategy:
/// - Loading (no cached rows and no session plays yet): spinner.
/// - Empty (server list empty and no session plays): "No history yet".
/// - Offline / sync error: the cached server order stays on screen; when a
///   sync error is present a compact "saved history" notice is shown.
/// - Fetch error with nothing to show: error state with a Retry button that
///   calls `refreshHistory`.
///
/// Gap: Jellyfin exposes no "clear history" endpoint, so unlike the old
/// local-only list this History is not clearable; the Clear button was
/// removed instead of faking a local-only clear that would diverge from the
/// server.
class HistoryList extends ConsumerWidget {
  const HistoryList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackProvider);
    final serverStream = ref.watch(recentlyPlayedStreamProvider);
    final syncError = ref.watch(appControllerProvider).syncError;
    return ListenableBuilder(
      listenable: playback,
      builder: (context, _) {
        final sessionTracks = playback.history;
        return StreamBuilder<List<Track>>(
          stream: serverStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData &&
                sessionTracks.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            final hasError = snapshot.hasError;
            final serverTracks = snapshot.data ?? const <Track>[];
            final merged = mergeRecentlyPlayed(
              serverTracks: serverTracks,
              sessionTracks: sessionTracks,
            );
            if (merged.isEmpty) {
              if (hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SpotifinEmptyState(
                        icon: Icons.sync_problem_rounded,
                        title: 'Could not load history',
                        message: '${snapshot.error}',
                      ),
                      TextButton(
                        onPressed: () => ref
                            .read(appControllerProvider.notifier)
                            .refreshHistory(),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }
              return const SpotifinEmptyState(
                icon: Icons.history_rounded,
                title: 'No history yet',
                message: 'Tracks you play will show up here.',
              );
            }
            return Column(
              children: [
                if (hasError)
                  _HistoryErrorBanner(
                    message: '${snapshot.error}',
                    onRetry: () => ref
                        .read(appControllerProvider.notifier)
                        .refreshHistory(),
                  )
                else if (syncError != null)
                  const _HistoryOfflineBanner(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => ref
                        .read(appControllerProvider.notifier)
                        .refreshHistory(),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 112),
                      itemCount: merged.length,
                      itemBuilder: (context, index) => _HistoryRow(
                        key: ValueKey('$index-${merged[index].id}'),
                        track: merged[index],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _HistoryErrorBanner extends StatelessWidget {
  const _HistoryErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: SpotifinColors.raised,
        borderRadius: BorderRadius.circular(SpotifinRadii.small),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.sync_problem_rounded, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Showing saved history. $message',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    ),
  );
}

class _HistoryOfflineBanner extends StatelessWidget {
  const _HistoryOfflineBanner();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(8, 8, 8, 0),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: SpotifinColors.raised,
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, size: 18),
            SizedBox(width: 8),
            Expanded(child: Text('Offline — showing saved history.')),
          ],
        ),
      ),
    ),
  );
}

class _HistoryRow extends ConsumerStatefulWidget {
  const _HistoryRow({required this.track, super.key});

  final Track track;

  @override
  ConsumerState<_HistoryRow> createState() => _HistoryRowState();
}

class _HistoryRowState extends ConsumerState<_HistoryRow> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: ListTile(
      hoverColor: SpotifinColors.hover,
      onTap: () => ref.read(playbackProvider).playHistoryTrack(widget.track),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(SpotifinRadii.small),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Artwork(
              itemId: widget.track.albumId ?? widget.track.id,
              size: 44,
              borderRadius: 0,
            ),
            AnimatedOpacity(
              opacity: _hovered ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: const ColoredBox(
                color: Color(0x99000000),
                child: SizedBox.square(
                  dimension: 44,
                  child: Icon(Icons.play_arrow_rounded, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
      title: Text(
        widget.track.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        widget.track.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(
        Icons.history_rounded,
        size: 18,
        color: SpotifinColors.textMuted,
      ),
    ),
  );
}
