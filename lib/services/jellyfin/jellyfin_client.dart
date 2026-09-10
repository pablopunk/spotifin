import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;

import '../../storage/database.dart';
import 'session.dart';

class JellyfinException implements Exception {
  const JellyfinException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class JellyfinClient {
  JellyfinClient({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final http.Client _http;
  static const _clientName = 'Spotifin';
  static const _version = '1.0.0';

  Future<JellyfinSession> authenticate({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    final baseUrl = _normalizeServerUrl(serverUrl);
    final publicInfo = await _getPublicInfo(baseUrl);
    final response = await _http.post(
      Uri.parse('$baseUrl/Users/AuthenticateByName'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': _authorization('spotifin-login'),
      },
      body: jsonEncode({'Username': username.trim(), 'Pw': password}),
    );
    final body = _decodeResponse(response);
    final user = body['User'] as Map<String, dynamic>?;
    final token = body['AccessToken'] as String?;
    if (user == null || token == null) {
      throw const JellyfinException(
        'The server returned an incomplete sign-in response.',
      );
    }
    return JellyfinSession(
      serverUrl: baseUrl,
      serverId: (publicInfo['Id'] as String?) ?? '',
      userId: user['Id'] as String,
      userName: user['Name'] as String? ?? username.trim(),
      accessToken: token,
    );
  }

  Future<Map<String, dynamic>> _getPublicInfo(String baseUrl) async {
    final response = await _http.get(Uri.parse('$baseUrl/System/Info/Public'));
    return _decodeResponse(response);
  }

  Future<List<TracksCompanion>> fetchTracks(JellyfinSession session) async {
    final items = <TracksCompanion>[];
    var startIndex = 0;
    const pageSize = 500;
    while (true) {
      final uri = _uri(session, '/Users/${session.userId}/Items', {
        'IncludeItemTypes': 'Audio',
        'Recursive': 'true',
        'StartIndex': '$startIndex',
        'Limit': '$pageSize',
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Fields':
            'Genres,Tags,DateCreated,UserData,AlbumId,ArtistItems,ImageTags',
        'EnableUserData': 'true',
      });
      final body = await _getJson(session, uri);
      final page = (body['Items'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      items.addAll(page.map(_trackFromJson));
      startIndex += page.length;
      final total = body['TotalRecordCount'] as int? ?? startIndex;
      if (page.isEmpty || startIndex >= total) break;
    }
    return items;
  }

  Future<List<PlaylistsCompanion>> fetchPlaylists(
    JellyfinSession session,
  ) async {
    final body = await _getJson(
      session,
      _uri(session, '/Users/${session.userId}/Items', {
        'IncludeItemTypes': 'Playlist',
        'Recursive': 'true',
        'Fields': 'ImageTags',
      }),
    );
    final summaries = (body['Items'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final results = <PlaylistsCompanion>[];
    for (final summary in summaries) {
      final id = summary['Id'] as String;
      final content = await _getJson(
        session,
        _uri(session, '/Playlists/$id/Items', {'userId': session.userId}),
      );
      final ids = (content['Items'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>()
          .map((item) => item['Id'] as String)
          .toList();
      results.add(
        PlaylistsCompanion.insert(
          id: id,
          name: summary['Name'] as String? ?? 'Untitled playlist',
          trackIds: Value(jsonEncode(ids)),
          imageTag: Value(_primaryImageTag(summary)),
        ),
      );
    }
    return results;
  }

  Future<void> setFavorite(
    JellyfinSession session,
    String itemId,
    bool favorite,
  ) async {
    final uri = _uri(session, '/Users/${session.userId}/FavoriteItems/$itemId');
    final response = favorite
        ? await _http.post(uri, headers: _headers(session))
        : await _http.delete(uri, headers: _headers(session));
    _ensureSuccess(response);
  }

  Uri streamUri(JellyfinSession session, String itemId, {bool small = false}) {
    final query = <String, String>{
      'api_key': session.accessToken,
      if (!small) 'static': 'true',
      if (small) ...{
        'audioCodec': 'aac',
        'audioBitRate': '128000',
        'container': 'm4a',
      },
    };
    return _uri(session, '/Audio/$itemId/stream', query);
  }

  Uri imageUri(JellyfinSession session, String itemId, {int width = 500}) =>
      _uri(session, '/Items/$itemId/Images/Primary', {
        'maxWidth': '$width',
        'quality': '88',
        'api_key': session.accessToken,
      });

  Future<Map<String, dynamic>> _getJson(
    JellyfinSession session,
    Uri uri,
  ) async {
    final response = await _http.get(uri, headers: _headers(session));
    return _decodeResponse(response);
  }

  Map<String, String> _headers(JellyfinSession session) => {
    'Accept': 'application/json',
    'Authorization': _authorization(
      session.serverId,
      token: session.accessToken,
    ),
  };

  String _authorization(String deviceId, {String? token}) {
    final tokenPart = token == null ? '' : ', Token="$token"';
    return 'MediaBrowser Client="$_clientName", Device="Flutter", '
        'DeviceId="$deviceId", Version="$_version"$tokenPart';
  }

  Uri _uri(
    JellyfinSession session,
    String path, [
    Map<String, String>? query,
  ]) => Uri.parse('${session.serverUrl}$path').replace(queryParameters: query);

  String _normalizeServerUrl(String value) {
    var result = value.trim();
    if (!result.startsWith('http://') && !result.startsWith('https://')) {
      result = 'https://$result';
    }
    return result.replaceFirst(RegExp(r'/+$'), '');
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    _ensureSuccess(response);
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw const JellyfinException('The server returned invalid data.');
    }
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final message = switch (response.statusCode) {
      401 => 'The username or password is incorrect.',
      403 => 'This account cannot perform that action.',
      404 => 'The requested Jellyfin item no longer exists.',
      _ => 'Jellyfin request failed (${response.statusCode}).',
    };
    throw JellyfinException(message, statusCode: response.statusCode);
  }

  TracksCompanion _trackFromJson(Map<String, dynamic> json) {
    final userData = json['UserData'] as Map<String, dynamic>? ?? const {};
    final artists = (json['Artists'] as List<dynamic>? ?? const [])
        .cast<String>();
    final artistItems = (json['ArtistItems'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final labels = <String>{
      ...(json['Genres'] as List<dynamic>? ?? const []).cast<String>(),
      ...(json['Tags'] as List<dynamic>? ?? const []).cast<String>(),
    };
    return TracksCompanion.insert(
      id: json['Id'] as String,
      name: json['Name'] as String? ?? 'Untitled track',
      album: Value(json['Album'] as String? ?? ''),
      albumId: Value(json['AlbumId'] as String?),
      artist: Value(artists.isEmpty ? 'Unknown artist' : artists.join(', ')),
      artistIds: Value(
        jsonEncode(artistItems.map((artist) => artist['Id']).toList()),
      ),
      labels: Value(jsonEncode(labels.toList())),
      durationTicks: Value(json['RunTimeTicks'] as int? ?? 0),
      imageTag: Value(_primaryImageTag(json)),
      favorite: Value(userData['IsFavorite'] as bool? ?? false),
      playCount: Value(userData['PlayCount'] as int? ?? 0),
      lastPlayed: Value(
        DateTime.tryParse(userData['LastPlayedDate'] as String? ?? ''),
      ),
      dateCreated: Value(
        DateTime.tryParse(json['DateCreated'] as String? ?? ''),
      ),
    );
  }

  String? _primaryImageTag(Map<String, dynamic> json) {
    final tags = json['ImageTags'] as Map<String, dynamic>?;
    return tags?['Primary'] as String?;
  }
}
