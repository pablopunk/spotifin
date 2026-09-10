import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../storage/database.dart';
import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/session.dart';
import 'lyric_line.dart';

class LyricsService {
  LyricsService(this._jellyfin, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final JellyfinClient _jellyfin;
  final http.Client _http;

  Future<List<LyricLine>> find(JellyfinSession session, Track track) async {
    final jellyfin = await _jellyfin.fetchLyrics(session, track.id);
    if (jellyfin.isNotEmpty) return jellyfin;
    return _findLrcLib(track);
  }

  Future<List<LyricLine>> _findLrcLib(Track track) async {
    final uri = Uri.https('lrclib.net', '/api/get', {
      'track_name': track.name,
      'artist_name': track.artist,
      if (track.album.isNotEmpty) 'album_name': track.album,
      if (track.durationTicks > 0)
        'duration': '${track.durationTicks ~/ 10000000}',
    });
    final response = await _http.get(
      uri,
      headers: {'User-Agent': 'Spotifin/1.0'},
    );
    if (response.statusCode == 404) return const [];
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const [];
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final synced = body['syncedLyrics'] as String?;
    if (synced != null && synced.trim().isNotEmpty) return _parseLrc(synced);
    final plain = body['plainLyrics'] as String?;
    return plain
            ?.split('\n')
            .where((line) => line.trim().isNotEmpty)
            .map((line) => LyricLine(line.trim()))
            .toList() ??
        const [];
  }

  List<LyricLine> _parseLrc(String value) {
    final timestamp = RegExp(r'^\[(\d+):(\d+(?:\.\d+)?)\](.*)$');
    return value
        .split('\n')
        .map(timestamp.firstMatch)
        .whereType<RegExpMatch>()
        .map((match) {
          final minutes = int.parse(match.group(1)!);
          final seconds = double.parse(match.group(2)!);
          return LyricLine(
            match.group(3)!.trim(),
            Duration(milliseconds: ((minutes * 60 + seconds) * 1000).round()),
          );
        })
        .where((line) => line.text.isNotEmpty)
        .toList();
  }
}
