import 'dart:async';

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
  Timer? _debounce;
  Stream<List<Track>> _results = const Stream.empty();

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _search(String value) {
    _debounce?.cancel();
    setState(() => _query = value.trim());
    if (_query.isEmpty) {
      setState(() => _results = const Stream.empty());
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      final words = _query.toLowerCase().split(RegExp(r'\s+'));
      setState(() {
        _results = ref.read(databaseProvider).searchTracks(words);
      });
    });
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Track>>(
    stream: _results,
    builder: (context, snapshot) {
      final results = snapshot.data ?? const [];
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
                onChanged: _search,
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
