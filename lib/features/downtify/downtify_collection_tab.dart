import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/features.dart';
import '../../app/providers.dart';
import '../../services/downtify/downtify_models.dart';
import '../../services/search/search_text.dart';
import '../../storage/database.dart';
import '../common/design_system.dart';
import 'downtify_song_results.dart';

class DowntifyCollectionSearch {
  const DowntifyCollectionSearch.artist(this.artist) : album = null;

  const DowntifyCollectionSearch.album({
    required String this.album,
    required this.artist,
  });

  final String artist;
  final String? album;

  String get query => [artist, ?album].join(' ');

  List<DowntifySong> filter(List<DowntifySong> songs) {
    final byArtist = songs.where(_creditsArtist).toList();
    final album = this.album;
    if (album == null) return byArtist;
    final fromAlbum = byArtist
        .where((song) => _sameName(song.albumName, album))
        .toList();
    return [
      ...fromAlbum,
      ...byArtist.where((song) => !fromAlbum.contains(song)),
    ];
  }

  bool _creditsArtist(DowntifySong song) =>
      song.artists.any((name) => _sameName(name, artist));

  static bool _sameName(String a, String b) =>
      normalizeSearchText(a).trim() == normalizeSearchText(b).trim();

  @override
  bool operator ==(Object other) =>
      other is DowntifyCollectionSearch &&
      other.artist == artist &&
      other.album == album;

  @override
  int get hashCode => Object.hash(artist, album);
}

final downtifyCollectionSongsProvider = FutureProvider.autoDispose
    .family<List<DowntifySong>, DowntifyCollectionSearch>((ref, search) async {
      final origin = ref.watch(
        downtifyControllerProvider.select(
          (state) => state.available ? state.serverUrl : null,
        ),
      );
      if (origin == null) return const [];
      final songs = await ref
          .read(downtifyClientProvider)
          .search(origin, search.query);
      return search.filter(songs);
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
