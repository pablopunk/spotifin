import '../../storage/database.dart';
import 'downtify_models.dart';

class DowntifyMatcher {
  const DowntifyMatcher();

  Track? findMatch(DowntifySong song, Iterable<Track> tracks) {
    final title = _normalize(song.name);
    final artists = song.artists
        .map(_normalize)
        .where((value) => value.isNotEmpty)
        .toSet();
    final matches = tracks.where((track) {
      if (_normalize(track.name) != title) return false;
      final localArtists = track.artist
          .split(RegExp(r'[,;]'))
          .map(_normalize)
          .where((value) => value.isNotEmpty);
      return artists.isNotEmpty && localArtists.any(artists.contains);
    }).toList();
    if (matches.length <= 1 || song.duration == null) {
      return matches.firstOrNull;
    }
    return matches.where((track) {
      final difference =
          (track.durationTicks ~/ 10000000) - song.duration!.inSeconds;
      return difference.abs() <= 5;
    }).firstOrNull;
  }

  bool isDuplicate(DowntifySong song, Iterable<Track> tracks) =>
      findMatch(song, tracks) != null;

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}
