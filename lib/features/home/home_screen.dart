import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/features.dart';
import '../../app/state/downtify_controller.dart';
import '../../app/theme.dart';
import '../../storage/database.dart';
import '../../services/mixes/mix_generator.dart';
import '../../services/downtify/downtify_matcher.dart';
import '../../services/downtify/downtify_models.dart';
import '../common/artwork.dart';
import '../common/album_context_menu.dart';
import '../common/design_system.dart';
import '../common/track_tile.dart';
import '../downtify/external_track_tile.dart';
import '../library/library_screen.dart';
import 'playlists_section.dart';

enum _SearchFilter { all, songs, artists, albums, downtify }

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({this.searchFocusNode, super.key});

  final FocusNode? searchFocusNode;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<Track>? _cachedTracks;
  _HomeCatalog? _cachedCatalog;
  late final FocusNode _searchFocusNode;
  Timer? _searchDebounce;
  String _query = '';
  _SearchFilter _searchFilter = _SearchFilter.all;
  Stream<List<Track>> _searchResults = const Stream.empty();

  @override
  void initState() {
    super.initState();
    _searchFocusNode = widget.searchFocusNode ?? FocusNode();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    if (widget.searchFocusNode == null) _searchFocusNode.dispose();
    super.dispose();
  }

  void _search(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    setState(() {
      _query = query;
      if (query.isEmpty) _searchFilter = _SearchFilter.all;
    });
    if (query.isEmpty) {
      if (AppFeatures.downtify) {
        ref.read(downtifyControllerProvider.notifier).search('');
      }
      setState(() => _searchResults = const Stream.empty());
      return;
    }
    if (AppFeatures.downtify) {
      ref.read(downtifyControllerProvider.notifier).search(query);
    }
    _searchDebounce = Timer(const Duration(milliseconds: 40), () {
      if (!mounted || query != _query) return;
      final words = query.toLowerCase().split(RegExp(r'\s+'));
      setState(() {
        _searchResults = ref.read(databaseProvider).searchTracks(words);
      });
    });
  }

  _HomeCatalog _catalogFor(List<Track> tracks) {
    if (identical(_cachedTracks, tracks)) return _cachedCatalog!;
    _cachedTracks = tracks;
    return _cachedCatalog = _HomeCatalog.fromTracks(tracks);
  }

  Future<void> _saveMix(DailyMix mix) async {
    var playlistName = mix.name;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save mix as playlist'),
        content: TextFormField(
          initialValue: playlistName,
          autofocus: true,
          onChanged: (value) => playlistName = value,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, playlistName),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await ref
        .read(appControllerProvider.notifier)
        .createPlaylist(name, mix.tracks.map((track) => track.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    final downtify = AppFeatures.downtify
        ? ref.watch(downtifyControllerProvider)
        : const DowntifyState(availability: DowntifyAvailability.unconfigured);
    final externalAvailable = AppFeatures.downtify && downtify.available;
    final filter = externalAvailable
        ? _searchFilter
        : _searchFilter == _SearchFilter.downtify
        ? _SearchFilter.all
        : _searchFilter;
    return StreamBuilder<List<Track>>(
      stream: ref.watch(databaseProvider).watchTracks(),
      builder: (context, snapshot) {
        final tracks = snapshot.data ?? const [];
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final catalog = _catalogFor(tracks);
        return RefreshIndicator(
          onRefresh: ref.read(appControllerProvider.notifier).refresh,
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                toolbarHeight: 80,
                titleSpacing: SpotifinSpacing.lg,
                title: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: SearchBar(
                      focusNode: _searchFocusNode,
                      hintText: 'What do you want to listen to?',
                      leading: const Icon(Icons.search_rounded),
                      onChanged: _search,
                    ),
                  ),
                ),
                actions: [
                  IconButton(
                    tooltip: 'Refresh library',
                    onPressed: ref.watch(appControllerProvider).syncing
                        ? null
                        : ref.read(appControllerProvider.notifier).refresh,
                    icon: ref.watch(appControllerProvider).syncing
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              if (ref.watch(appControllerProvider).syncError
                  case final message?)
                SliverToBoxAdapter(
                  child: _SavedLibraryNotice(message: message),
                ),
              if (_query.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _SearchFilters(
                    selected: filter,
                    filters: externalAvailable
                        ? _SearchFilter.values
                        : _SearchFilter.values
                              .where(
                                (filter) => filter != _SearchFilter.downtify,
                              )
                              .toList(),
                    onSelected: (filter) =>
                        setState(() => _searchFilter = filter),
                  ),
                ),
                _SearchResults(
                  query: _query,
                  filter: filter,
                  results: _searchResults,
                  libraryTracks: tracks,
                  externalResults: downtify.results,
                  externalSearching: downtify.searching,
                ),
              ] else if (tracks.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyCatalog(),
                )
              else ...[
                if (catalog.recent.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _HorizontalSection(
                      title: 'Recently played',
                      tracks: catalog.recent.take(12).toList(),
                      contextTracks: catalog.recent,
                    ),
                  ),
                SliverToBoxAdapter(
                  child: _HorizontalSection(
                    title: 'Recently added',
                    tracks: catalog.added.take(12).toList(),
                    contextTracks: catalog.added,
                  ),
                ),
                SliverToBoxAdapter(child: PlaylistsSection(tracks: tracks)),
                if (catalog.favorites.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _HorizontalSection(
                      title: 'Favorites',
                      tracks: catalog.favorites.take(12).toList(),
                      contextTracks: catalog.favorites,
                    ),
                  ),
                ...catalog.mixes
                    .take(3)
                    .map(
                      (mix) => SliverToBoxAdapter(
                        child: _HorizontalSection(
                          title: mix.name,
                          tracks: mix.tracks.take(12).toList(),
                          contextTracks: mix.tracks,
                          action: IconButton(
                            tooltip: 'Save ${mix.name} as playlist',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _saveMix(mix),
                            icon: const Icon(Icons.playlist_add_rounded),
                          ),
                        ),
                      ),
                    ),
                const SliverToBoxAdapter(child: SpotifinPageTitle('All songs')),
                SliverList.builder(
                  itemCount: tracks.length,
                  itemBuilder: (context, index) =>
                      TrackTile(track: tracks[index], contextTracks: tracks),
                ),
              ],
              SliverToBoxAdapter(
                child: SizedBox(height: SpotifinChromeInsets.bottomOf(context)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SavedLibraryNotice extends StatelessWidget {
  const _SavedLibraryNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      SpotifinSpacing.lg,
      SpotifinSpacing.sm,
      SpotifinSpacing.lg,
      0,
    ),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: SpotifinColors.raised,
        borderRadius: BorderRadius.circular(SpotifinRadii.small),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SpotifinSpacing.md,
          vertical: SpotifinSpacing.sm,
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_rounded, size: 18),
            const SizedBox(width: SpotifinSpacing.sm),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.query,
    required this.filter,
    required this.results,
    required this.libraryTracks,
    required this.externalResults,
    required this.externalSearching,
  });

  final String query;
  final _SearchFilter filter;
  final Stream<List<Track>> results;
  final List<Track> libraryTracks;
  final List<DowntifySong> externalResults;
  final bool externalSearching;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Track>>(
    stream: results,
    builder: (context, snapshot) {
      final tracks = snapshot.data ?? const [];
      final artists = _matchingGroups(
        tracks,
        query,
        (track) => track.artist.split(';'),
      );
      final albums = _matchingGroups(tracks, query, (track) => [track.album]);
      final visibleExternal = filter == _SearchFilter.all
          ? externalResults
                .where(
                  (song) =>
                      !const DowntifyMatcher().isDuplicate(song, libraryTracks),
                )
                .toList()
          : filter == _SearchFilter.downtify
          ? externalResults
          : const <DowntifySong>[];
      final localHasResults = switch (filter) {
        _SearchFilter.all =>
          tracks.isNotEmpty || artists.isNotEmpty || albums.isNotEmpty,
        _SearchFilter.songs => tracks.isNotEmpty,
        _SearchFilter.artists => artists.isNotEmpty,
        _SearchFilter.albums => albums.isNotEmpty,
        _SearchFilter.downtify => false,
      };
      final hasResults = filter == _SearchFilter.downtify
          ? visibleExternal.isNotEmpty
          : localHasResults || visibleExternal.isNotEmpty;
      if (!hasResults) {
        if (filter == _SearchFilter.downtify && externalSearching) {
          return const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return const SliverFillRemaining(
          hasScrollBody: false,
          child: SpotifinEmptyState(
            icon: Icons.search_off_rounded,
            title: 'No matches',
            message: 'Try another song, artist, or album.',
          ),
        );
      }
      return SliverMainAxisGroup(
        slivers: filter == _SearchFilter.downtify
            ? [
                _ExternalSongResults(
                  songs: visibleExternal,
                  libraryTracks: libraryTracks,
                ),
              ]
            : switch (filter) {
                _SearchFilter.all => [
                  if (artists.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: SpotifinPageTitle('Artists'),
                    ),
                    _CollectionResults(
                      entries: artists.take(4).toList(),
                      artist: true,
                    ),
                  ],
                  if (albums.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: SpotifinPageTitle('Albums'),
                    ),
                    _CollectionResults(entries: albums.take(4).toList()),
                  ],
                  if (tracks.isNotEmpty) ...[
                    const SliverToBoxAdapter(child: SpotifinPageTitle('Songs')),
                    _SongResults(tracks: tracks),
                  ],
                  if (visibleExternal.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: SpotifinPageTitle('Add to library'),
                    ),
                    _ExternalSongResults(songs: visibleExternal),
                  ],
                ],
                _SearchFilter.songs => [
                  if (tracks.isNotEmpty) _SongResults(tracks: tracks),
                ],
                _SearchFilter.artists => [
                  _CollectionResults(entries: artists, artist: true),
                ],
                _SearchFilter.albums => [_CollectionResults(entries: albums)],
                _SearchFilter.downtify => const [],
              },
      );
    },
  );
}

class _SearchFilters extends StatelessWidget {
  const _SearchFilters({
    required this.selected,
    required this.filters,
    required this.onSelected,
  });

  final _SearchFilter selected;
  final List<_SearchFilter> filters;
  final ValueChanged<_SearchFilter> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: SpotifinSpacing.lg),
    child: DefaultTabController(
      length: filters.length,
      initialIndex: filters.indexOf(selected),
      child: SpotifinTabBar(
        labels: filters.map(_filterLabel).toList(),
        onTap: (index) => onSelected(filters[index]),
      ),
    ),
  );
}

class _SongResults extends StatelessWidget {
  const _SongResults({required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context) => SliverList.builder(
    itemCount: tracks.length,
    itemBuilder: (context, index) =>
        TrackTile(track: tracks[index], contextTracks: tracks),
  );
}

class _ExternalSongResults extends StatelessWidget {
  const _ExternalSongResults({
    required this.songs,
    this.libraryTracks = const [],
  });

  final List<DowntifySong> songs;
  final List<Track> libraryTracks;

  @override
  Widget build(BuildContext context) {
    const matcher = DowntifyMatcher();
    final matches = {
      for (final song in songs) song.id: matcher.findMatch(song, libraryTracks),
    };
    final matchedTracks = matches.values.whereType<Track>().toList();
    return SliverList.builder(
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        final match = matches[song.id];
        return match == null
            ? ExternalTrackTile(song: song)
            : TrackTile(track: match, contextTracks: matchedTracks);
      },
    );
  }
}

class _CollectionResults extends StatelessWidget {
  const _CollectionResults({required this.entries, this.artist = false});

  final List<MapEntry<String, List<Track>>> entries;
  final bool artist;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: SpotifinSpacing.md),
    sliver: SliverGrid.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 238,
        crossAxisSpacing: SpotifinSpacing.md,
        mainAxisSpacing: SpotifinSpacing.md,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final first = entry.value.first;
        final card = SpotifinCollectionCard(
          artwork: LayoutBuilder(
            builder: (context, constraints) => Artwork(
              itemId: first.albumId ?? first.id,
              size: constraints.biggest.shortestSide,
              borderRadius: artist
                  ? constraints.biggest.shortestSide / 2
                  : SpotifinRadii.small,
            ),
          ),
          title: entry.key,
          subtitle: '${entry.value.length} songs',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CollectionScreen(
                title: entry.key,
                tracks: entry.value,
                icon: artist ? Icons.person_rounded : Icons.album_rounded,
              ),
            ),
          ),
        );
        return artist
            ? card
            : AlbumContextMenu(
                title: entry.key,
                tracks: entry.value,
                child: card,
              );
      },
    ),
  );
}

List<MapEntry<String, List<Track>>> _matchingGroups(
  List<Track> tracks,
  String query,
  Iterable<String> Function(Track) names,
) {
  final words = query.toLowerCase().split(RegExp(r'\s+'));
  final groups = <String, List<Track>>{};
  for (final track in tracks) {
    for (final rawName in names(track)) {
      final name = rawName.trim();
      final normalized = name.toLowerCase();
      if (name.isEmpty || !words.every(normalized.contains)) continue;
      groups.putIfAbsent(name, () => []).add(track);
    }
  }
  final entries = groups.entries.toList();
  entries.sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
  return entries;
}

String _filterLabel(_SearchFilter filter) => switch (filter) {
  _SearchFilter.all => 'All',
  _SearchFilter.songs => 'Songs',
  _SearchFilter.artists => 'Artists',
  _SearchFilter.albums => 'Albums',
  _SearchFilter.downtify => 'Downtify',
};

class _HomeCatalog {
  const _HomeCatalog({
    required this.recent,
    required this.added,
    required this.favorites,
    required this.mixes,
  });

  factory _HomeCatalog.fromTracks(List<Track> tracks) {
    final recent = tracks.where((track) => track.lastPlayed != null).toList()
      ..sort((a, b) => b.lastPlayed!.compareTo(a.lastPlayed!));
    final added = [...tracks]
      ..sort(
        (a, b) => (b.dateCreated ?? DateTime(0)).compareTo(
          a.dateCreated ?? DateTime(0),
        ),
      );
    return _HomeCatalog(
      recent: recent,
      added: added,
      favorites: tracks.where((track) => track.favorite).toList(),
      mixes: const MixGenerator().generate(tracks, DateTime.now()),
    );
  }

  final List<Track> recent;
  final List<Track> added;
  final List<Track> favorites;
  final List<DailyMix> mixes;
}

class _HorizontalSection extends StatelessWidget {
  const _HorizontalSection({
    required this.title,
    required this.tracks,
    required this.contextTracks,
    this.action,
  });
  final String title;
  final List<Track> tracks;
  final List<Track> contextTracks;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: SpotifinSpacing.xl),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SpotifinSpacing.lg),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              if (action != null) const SizedBox(width: SpotifinSpacing.xs),
              ?action,
            ],
          ),
        ),
        const SizedBox(height: SpotifinSpacing.sm),
        SizedBox(
          height: 224,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: SpotifinSpacing.lg),
            scrollDirection: Axis.horizontal,
            itemCount: tracks.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: SpotifinSpacing.md),
            itemBuilder: (context, index) {
              final track = tracks[index];
              return TrackContextMenu(
                track: track,
                contextTracks: contextTracks,
                child: DraggableTrack(
                  track: track,
                  child: SizedBox(
                    width: 164,
                    child: Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(SpotifinRadii.card),
                        onTap: () =>
                            ProviderScope.containerOf(context)
                                .read(playbackProvider)
                                .playTrack(track, contextTracks),
                        child: Padding(
                          padding: const EdgeInsets.all(SpotifinSpacing.sm),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Artwork(
                                itemId: track.albumId ?? track.id,
                                size: 140,
                                borderRadius: SpotifinRadii.small,
                              ),
                              const SizedBox(height: SpotifinSpacing.sm),
                              Text(
                                track.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                track.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _EmptyCatalog extends StatelessWidget {
  const _EmptyCatalog();

  @override
  Widget build(BuildContext context) => const SpotifinEmptyState(
    icon: Icons.library_music_outlined,
    title: 'No music found',
    message: 'Check that this Jellyfin account can access a music library.',
  );
}
