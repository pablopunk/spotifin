import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../storage/database.dart';
import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/session.dart';

enum AlbumKind { album, ep, single, other }

class AlbumTypeService {
  AlbumTypeService(this._jellyfin, this._database, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  static const _headers = {
    'User-Agent': 'Spotifin/1.0.0 (https://github.com/pablopunk/spotifin)',
  };
  static const _minRequestGap = Duration(milliseconds: 1100);
  static const _maxReleaseGroupsPerRequest = 50;

  final JellyfinClient _jellyfin;
  final AppDatabase _database;
  final http.Client _http;
  DateTime? _lastLookup;

  Future<Map<String, AlbumKind>> resolve(
    JellyfinSession? session,
    Iterable<String> albumIds,
  ) async {
    final ids = albumIds.toSet().toList();
    if (ids.isEmpty) return const {};
    final rows = await _database.albumKindsFor(ids);
    final cached = _kinds(rows);
    final missing = ids.where((id) => !rows.containsKey(id)).toList();
    if (missing.isEmpty || session == null) return cached;
    try {
      final releaseGroups = await _jellyfin.fetchAlbumReleaseGroups(
        session,
        missing,
      );
      final looked = await _lookup(releaseGroups.values.toSet().toList());
      final fresh = <String, String>{};
      for (final albumId in missing) {
        final releaseGroup = releaseGroups[albumId];
        if (releaseGroup == null) {
          fresh[albumId] = '';
          continue;
        }
        if (looked[releaseGroup] case final kind?) fresh[albumId] = kind.name;
      }
      await _database.saveAlbumKinds(fresh);
      return {...cached, ..._kinds(fresh)};
    } catch (_) {
      return cached;
    }
  }

  Map<String, AlbumKind> _kinds(Map<String, String> rows) {
    final kinds = <String, AlbumKind>{};
    for (final entry in rows.entries) {
      final kind = AlbumKind.values.asNameMap()[entry.value];
      if (kind != null) kinds[entry.key] = kind;
    }
    return kinds;
  }

  Future<Map<String, AlbumKind>> _lookup(List<String> releaseGroupIds) async {
    final kinds = <String, AlbumKind>{};
    for (
      var start = 0;
      start < releaseGroupIds.length;
      start += _maxReleaseGroupsPerRequest
    ) {
      final batch = releaseGroupIds
          .skip(start)
          .take(_maxReleaseGroupsPerRequest)
          .toList();
      kinds.addAll(await _lookupBatch(batch));
    }
    return kinds;
  }

  Future<Map<String, AlbumKind>> _lookupBatch(
    List<String> releaseGroupIds,
  ) async {
    await _throttle();
    final query = releaseGroupIds.map((id) => 'rgid:$id').join('%20OR%20');
    final response = await _http.get(
      Uri.parse(
        'https://musicbrainz.org/ws/2/release-group?query=$query&fmt=json&limit=100',
      ),
      headers: _headers,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const {};
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final groups = (body['release-groups'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final kinds = <String, AlbumKind>{};
    for (final group in groups) {
      final id = group['id'] as String?;
      final kind = _kind('${group['primary-type']}');
      if (id != null && kind != null) kinds[id] = kind;
    }
    return kinds;
  }

  AlbumKind? _kind(String primaryType) => switch (primaryType.toLowerCase()) {
    'album' => AlbumKind.album,
    'ep' => AlbumKind.ep,
    'single' => AlbumKind.single,
    'broadcast' || 'other' => AlbumKind.other,
    _ => null,
  };

  Future<void> _throttle() async {
    final last = _lastLookup;
    if (last != null) {
      final wait = _minRequestGap - DateTime.now().difference(last);
      if (wait > Duration.zero) await Future.delayed(wait);
    }
    _lastLookup = DateTime.now();
  }
}
