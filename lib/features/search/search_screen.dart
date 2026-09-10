import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../storage/database.dart';
import '../common/design_system.dart';
import '../common/track_tile.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({required this.focusNode, super.key});

  final FocusNode focusNode;

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
    _debounce = Timer(const Duration(milliseconds: 80), () {
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
          const SliverAppBar(
            pinned: true,
            expandedHeight: 112,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: EdgeInsets.fromLTRB(20, 0, 20, 18),
              title: Text('Search'),
            ),
          ),
          SliverToBoxAdapter(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: SearchBar(
                    focusNode: widget.focusNode,
                    autoFocus: false,
                    hintText: 'What do you want to listen to?',
                    leading: const Icon(
                      Icons.search_rounded,
                      color: SpotifinColors.text,
                    ),
                    onChanged: _search,
                  ),
                ),
              ),
            ),
          ),
          if (_query.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: SpotifinEmptyState(
                icon: Icons.search_rounded,
                title: 'Find your favorites',
                message: 'Search your complete Jellyfin music library.',
              ),
            )
          else if (results.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: SpotifinEmptyState(
                icon: Icons.search_off_rounded,
                title: 'No matches',
                message: 'Try another song, artist, or album.',
              ),
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
