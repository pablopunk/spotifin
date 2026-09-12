import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../storage/database.dart';
import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/session.dart';
import 'lyric_line.dart';

class LyricsService {
  LyricsService(this._jellyfin, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  static const _headers = {'Lrclib-Client': 'Spotifin/1.0'};
  static const _durationTolerance = 3;

  final JellyfinClient _jellyfin;
  final http.Client _http;

  Future<List<LyricLine>> find(JellyfinSession session, Track track) async {
    final jellyfin = await _jellyfin.fetchLyrics(session, track.id);
    if (jellyfin.isNotEmpty) return jellyfin;
    return _findLrcLib(track);
  }

  Future<List<LyricLine>> _findLrcLib(Track track) async {
    final exact = await _record('/api/get', {
      'track_name': track.name,
      'artist_name': track.artist,
      if (track.album.isNotEmpty) 'album_name': track.album,
      if (track.durationTicks > 0)
        'duration': '${track.durationTicks ~/ 10000000}',
    });
    if (exact != null) {
      final lyrics = _lyricsFrom(exact);
      if (lyrics.isNotEmpty) return lyrics;
    }
    for (final query in _searchQueries(track)) {
      final match = _bestMatch(await _search(query), track);
      if (match == null) continue;
      final lyrics = _lyricsFrom(match);
      if (lyrics.isNotEmpty) return lyrics;
    }
    return const [];
  }

  Iterable<Map<String, String>> _searchQueries(Track track) sync* {
    final artist = _primaryArtist(track.artist);
    final title = track.name.trim();
    yield {'track_name': title, 'artist_name': artist};
    final rewritten = _rewriteTitle(title);
    if (rewritten != title) {
      yield {'track_name': rewritten, 'artist_name': artist};
    }
    yield {'q': '${_normalize(rewritten)} $artist'};
  }

  Map<String, dynamic>? _bestMatch(
    List<Map<String, dynamic>> records,
    Track track,
  ) {
    Map<String, dynamic>? best;
    var bestScore = 0;
    for (final record in records) {
      final score = _score(record, track);
      if (score <= bestScore) continue;
      best = record;
      bestScore = score;
    }
    return bestScore >= 4 ? best : null;
  }

  int _score(Map<String, dynamic> record, Track track) {
    if (record['instrumental'] == true) return -1;
    if (!_hasLyrics(record)) return -1;
    if (!_artistMatches(record, track)) return -1;
    final title = _normalize('${record['trackName'] ?? ''}');
    final wanted = _normalize(track.name);
    if (wanted.isEmpty) return -1;
    var score = 0;
    if (title == wanted) {
      score += 4;
    } else if (title.contains(wanted) || wanted.contains(title)) {
      score += 2;
    } else {
      return -1;
    }
    final duration = (record['duration'] as num?)?.toDouble();
    if (duration != null && track.durationTicks > 0) {
      final delta = (duration - track.durationTicks / 10000000).abs();
      if (delta <= _durationTolerance) {
        score += 2;
      } else if (delta <= 15) {
        score += 1;
      }
    }
    return score;
  }

  bool _artistMatches(Map<String, dynamic> record, Track track) {
    final wanted = _normalize(_primaryArtist(track.artist));
    if (wanted.isEmpty) return true;
    final candidate = _normalize('${record['artistName'] ?? ''}');
    return candidate.isNotEmpty &&
        (candidate.contains(wanted) || wanted.contains(candidate));
  }

  Future<Map<String, dynamic>?> _record(
    String path,
    Map<String, String> query,
  ) async {
    final body = await _get(path, query);
    return body is Map<String, dynamic> ? body : null;
  }

  Future<List<Map<String, dynamic>>> _search(Map<String, String> query) async {
    final body = await _get('/api/search', query);
    if (body is! List) return const [];
    return body.whereType<Map<String, dynamic>>().toList();
  }

  Future<Object?> _get(String path, Map<String, String> query) async {
    final response = await _http.get(
      Uri.https('lrclib.net', path, query),
      headers: _headers,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    return jsonDecode(response.body);
  }

  bool _hasLyrics(Map<String, dynamic> record) =>
      (record['syncedLyrics'] as String?)?.trim().isNotEmpty == true ||
      (record['plainLyrics'] as String?)?.trim().isNotEmpty == true;

  List<LyricLine> _lyricsFrom(Map<String, dynamic> record) {
    final synced = record['syncedLyrics'] as String?;
    if (synced != null && synced.trim().isNotEmpty) return _parseLrc(synced);
    final plain = record['plainLyrics'] as String?;
    return plain
            ?.split('\n')
            .where((line) => line.trim().isNotEmpty)
            .map((line) => LyricLine(line.trim()))
            .toList() ??
        const [];
  }

  String _primaryArtist(String artist) => artist.split(';').first.trim();

  String _rewriteTitle(String title) => title.replaceAllMapped(
    RegExp(r'\byou\b', caseSensitive: false),
    (match) => match[0]!.startsWith('Y') ? 'U' : 'u',
  );

  String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\byou\b'), 'u')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

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
