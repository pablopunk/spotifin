import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../storage/database.dart';
import '../common/track_tile.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Track>>(
    stream: ref.watch(databaseProvider).watchTracks(),
    builder: (context, snapshot) {
      final all = snapshot.data ?? const [];
      final words = _query.trim().toLowerCase().split(RegExp(r'\s+'));
      final results = _query.trim().isEmpty
          ? const <Track>[]
          : all.where((track) {
              final value = '${track.name} ${track.artist} ${track.album}'
                  .toLowerCase();
              return words.every(value.contains);
            }).toList();
      return CustomScrollView(
        slivers: [
          const SliverAppBar.large(title: Text('Search')),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SearchBar(
                autoFocus: false,
                hintText: 'Songs, artists, and albums',
                leading: const Icon(Icons.search_rounded),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
          ),
          if (_query.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text('Search your complete Jellyfin music library.'),
              ),
            )
          else if (results.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('No matches')),
            )
          else
            SliverList.builder(
              itemCount: results.length,
              itemBuilder: (context, index) =>
                  TrackTile(track: results[index], contextTracks: results),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      );
    },
  );
}
