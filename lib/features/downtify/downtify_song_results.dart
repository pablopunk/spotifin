import 'package:flutter/material.dart';

import '../../services/downtify/downtify_matcher.dart';
import '../../services/downtify/downtify_models.dart';
import '../../storage/database.dart';
import '../common/track_tile.dart';
import 'external_track_tile.dart';

class DowntifySongResults extends StatelessWidget {
  const DowntifySongResults({
    required this.songs,
    this.libraryTracks = const [],
    super.key,
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
