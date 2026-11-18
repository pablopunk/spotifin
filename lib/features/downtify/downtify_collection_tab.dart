import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/features.dart';
import '../../app/providers.dart';
import '../../services/downtify/downtify_collection_search.dart';
import '../../services/downtify/downtify_models.dart';
import '../../storage/database.dart';
import '../common/design_system.dart';
import 'downtify_song_results.dart';

export '../../services/downtify/downtify_collection_search.dart';

final downtifyCollectionSongsProvider = FutureProvider.autoDispose
    .family<List<DowntifySong>, DowntifyCollectionSearch>((ref, search) async {
      final origin = ref.watch(
        downtifyControllerProvider.select(
          (state) => state.available ? state.serverUrl : null,
        ),
      );
      if (origin == null) return const [];
      return search.load(ref.read(downtifyClientProvider), origin);
    });

bool watchDowntifyAvailable(WidgetRef ref) =>
    AppFeatures.downtify &&
    ref.watch(downtifyControllerProvider.select((state) => state.available));

class DowntifyCollectionTab extends ConsumerWidget {
  const DowntifyCollectionTab({
    required this.search,
    required this.libraryTracks,
    super.key,
  });

  final DowntifyCollectionSearch search;
  final List<Track> libraryTracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      switch (ref.watch(downtifyCollectionSongsProvider(search))) {
        AsyncData(:final value) when value.isNotEmpty => CustomScrollView(
          slivers: [
            DowntifySongResults(songs: value, libraryTracks: libraryTracks),
            SliverToBoxAdapter(
              child: SizedBox(height: SpotifinChromeInsets.bottomOf(context)),
            ),
          ],
        ),
        AsyncData() => const _DowntifyMessage(
          icon: Icons.search_off_rounded,
          title: 'No Downtify results',
        ),
        AsyncError() => const _DowntifyMessage(
          icon: Icons.cloud_off_rounded,
          title: 'Downtify is unavailable',
        ),
        _ => const Center(child: CircularProgressIndicator()),
      };
}

class _DowntifyMessage extends StatelessWidget {
  const _DowntifyMessage({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: SpotifinEmptyState(icon: icon, title: title),
  );
}
