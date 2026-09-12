import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../storage/database.dart';
import '../lyrics/lyric_line.dart';
import 'remote_session.dart';
import 'session.dart';

class JellyfinException implements Exception {
  const JellyfinException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class JellyfinClient {
  JellyfinClient({
    http.Client? httpClient,
    Duration requestTimeout = const Duration(seconds: 10),
  }) : _http = _TimeoutClient(httpClient ?? http.Client(), requestTimeout);

  final http.Client _http;
  static const _clientName = 'Spotifin';
  static const _version = '1.0.0';

  void close() => _http.close();

  Future<JellyfinSession> authenticate({
    required String serverUrl,
    required String username,
    required String password,
    required String deviceId,
  }) async {
    final baseUrl = _normalizeServerUrl(serverUrl);
    final publicInfo = await _getPublicInfo(baseUrl);
    final response = await _http.post(
      Uri.parse('$baseUrl/Users/AuthenticateByName'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': _authorization(deviceId),
      },
      body: jsonEncode({'Username': username.trim(), 'Pw': password}),
    );
    final body = _decodeResponse(response, signingIn: true);
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
      deviceId: deviceId,
      userId: user['Id'] as String,
      userName: user['Name'] as String? ?? username.trim(),
      accessToken: token,
    );
  }

  Future<JellyfinSession> refreshSession(JellyfinSession session) async {
    final user = await _getJson(session, _uri(session, '/Users/Me'));
    return JellyfinSession(
      serverUrl: session.serverUrl,
      serverId: user['ServerId'] as String? ?? session.serverId,
      deviceId: session.deviceId,
      userId: user['Id'] as String? ?? session.userId,
      userName: user['Name'] as String? ?? session.userName,
      accessToken: session.accessToken,
    );
  }

  Future<Map<String, dynamic>> _getPublicInfo(String baseUrl) async {
    final response = await _http.get(Uri.parse('$baseUrl/System/Info/Public'));
    return _decodeResponse(response);
  }

  Future<List<TracksCompanion>> fetchTracks(
    JellyfinSession session, {
    Future<void> Function(List<TracksCompanion> page)? onPage,
  }) async {
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
        'Fields': 'Genres,Tags,DateCreated,UserData,AlbumId,ArtistItems,ImageTags,NormalizationGain',
        'EnableUserData': 'true',
      });
      final body = await _getJson(session, uri);
      final page = (body['Items'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      final rows = page.map(_trackFromJson).toList();
      items.addAll(rows);
      await onPage?.call(rows);
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
    final results = List<PlaylistsCompanion?>.filled(summaries.length, null);
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= summaries.length) return;
        results[index] = await _playlistFromSummary(session, summaries[index]);
      }
    }

    await Future.wait(List.generate(4, (_) => worker()));
    return results.cast<PlaylistsCompanion>();
  }

  Future<PlaylistsCompanion> _playlistFromSummary(
    JellyfinSession session,
    Map<String, dynamic> summary,
  ) async {
    final id = summary['Id'] as String;
    final content = await _getJson(
      session,
      _uri(session, '/Playlists/$id/Items', {'userId': session.userId}),
    );
    final ids = (content['Items'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map((item) => item['Id'] as String)
        .toList();
    return PlaylistsCompanion.insert(
      id: id,
      name: summary['Name'] as String? ?? 'Untitled playlist',
      trackIds: Value(jsonEncode(ids)),
      imageTag: Value(_primaryImageTag(summary)),
    );
  }

  Future<List<AlbumDatesCompanion>> fetchAlbumDates(
    JellyfinSession session,
  ) async {
    final dates = <AlbumDatesCompanion>[];
    var startIndex = 0;
    const pageSize = 500;
    while (true) {
      final body = await _getJson(
        session,
        _uri(session, '/Users/${session.userId}/Items', {
          'IncludeItemTypes': 'MusicAlbum',
          'Recursive': 'true',
          'StartIndex': '$startIndex',
          'Limit': '$pageSize',
          'SortBy': 'SortName',
          'SortOrder': 'Ascending',
        }),
      );
      final page = (body['Items'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      for (final item in page) {
        final id = item['Id'] as String?;
        final date = _premiereDate(item);
        if (id != null && date != null) {
          dates.add(
            AlbumDatesCompanion.insert(albumId: id, premiereDate: date),
          );
        }
      }
      startIndex += page.length;
      final total = body['TotalRecordCount'] as int? ?? startIndex;
      if (page.isEmpty || startIndex >= total) break;
    }
    return dates;
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

  Future<void> deleteItem(JellyfinSession session, String itemId) async {
    final response = await _http.delete(
      _uri(session, '/Items/$itemId'),
      headers: _headers(session),
    );
    _ensureSuccess(response);
  }

  Future<void> addToPlaylist(
    JellyfinSession session,
    String playlistId,
    List<String> trackIds,
  ) async {
    final response = await _http.post(
      _uri(session, '/Playlists/$playlistId/Items', {
        'ids': trackIds.join(','),
        'userId': session.userId,
      }),
      headers: _headers(session),
    );
    _ensureSuccess(response);
  }

  Future<void> createPlaylist(
    JellyfinSession session,
    String name,
    List<String> trackIds,
  ) async {
    final response = await _http.post(
      _uri(session, '/Playlists', {
        'name': name,
        'ids': trackIds.join(','),
        'userId': session.userId,
        'mediaType': 'Audio',
      }),
      headers: _headers(session),
    );
    _ensureSuccess(response);
  }

  Future<void> renamePlaylist(
    JellyfinSession session,
    String playlistId,
    String name,
  ) async {
    final response = await _http.post(
      _uri(session, '/Playlists/$playlistId'),
      headers: {..._headers(session), 'Content-Type': 'application/json'},
      body: jsonEncode({'Name': name}),
    );
    _ensureSuccess(response);
  }

  Future<void> logout(JellyfinSession session) async {
    final response = await _http.post(
      _uri(session, '/Sessions/Logout'),
      headers: _headers(session),
    );
    if (response.statusCode == 401) return;
    _ensureSuccess(response);
  }

  Future<void> requestLibraryRefresh(JellyfinSession session) async {
    final response = await _http.post(
      _uri(session, '/Library/Refresh'),
      headers: _headers(session),
    );
    _ensureSuccess(response);
  }

  Future<void> reportPlayback(
    JellyfinSession session,
    String endpoint,
    String itemId,
    Duration position, {
    required String playSessionId,
    bool paused = false,
    String? playlistItemId,
    List<Map<String, String>> queue = const [],
    int volume = 100,
    String repeatMode = 'RepeatNone',
    bool shuffle = false,
  }) async {
    final response = await _http.post(
      _uri(session, endpoint),
      headers: {..._headers(session), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'ItemId': itemId,
        'PositionTicks': position.inMicroseconds * 10,
        'IsPaused': paused,
        'CanSeek': true,
        'PlayMethod': 'DirectStream',
        'PlaySessionId': playSessionId,
        'PlaylistItemId': playlistItemId,
        'NowPlayingQueue': queue,
        'VolumeLevel': volume,
        'RepeatMode': repeatMode,
        'PlaybackOrder': shuffle ? 'Shuffle' : 'Default',
      }),
    );
    _ensureSuccess(response);
  }

  Future<List<RemoteSession>> fetchSessions(JellyfinSession session) async {
    final response = await _http.get(
      _uri(session, '/Sessions', {
        'controllableByUserId': session.userId,
        'activeWithinSeconds': '90',
      }),
      headers: _headers(session),
    );
    final body = _decodeResponseList(response);
    return body
        .whereType<Map<String, dynamic>>()
        .map(RemoteSession.fromJson)
        .where(
          (item) =>
              item.id.isNotEmpty &&
              item.userId == session.userId &&
              item.client == _clientName &&
              item.deviceId != session.deviceId &&
              item.supportsMediaControl &&
              item.isActive,
        )
        .toList(growable: false);
  }

  Future<void> advertiseRemoteCapabilities(JellyfinSession session) async {
    final response = await _http.post(
      _uri(session, '/Sessions/Capabilities/Full'),
      headers: {..._headers(session), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'PlayableMediaTypes': ['Audio'],
        'SupportedCommands': ['SetVolume', 'SetShuffleQueue', 'SetRepeatMode'],
        'SupportsMediaControl': true,
        'SupportsPersistentIdentifier': true,
      }),
    );
    _ensureSuccess(response);
  }

  Future<void> sendPlaystateCommand(
    JellyfinSession session,
    String sessionId,
    String command, {
    Duration? position,
  }) async {
    final response = await _http.post(
      _uri(session, '/Sessions/$sessionId/Playing/$command', {
        if (position != null)
          'seekPositionTicks': '${position.inMicroseconds * 10}',
      }),
      headers: _headers(session),
    );
    _ensureSuccess(response);
  }

  Future<void> sendGeneralCommand(
    JellyfinSession session,
    String sessionId,
    String name,
    Map<String, String> arguments,
  ) async {
    final response = await _http.post(
      _uri(session, '/Sessions/$sessionId/Command'),
      headers: {..._headers(session), 'Content-Type': 'application/json'},
      body: jsonEncode({'Name': name, 'Arguments': arguments}),
    );
    _ensureSuccess(response);
  }

  Future<void> sendPlayCommand(
    JellyfinSession session,
    String sessionId,
    List<String> itemIds, {
    int startIndex = 0,
    Duration position = Duration.zero,
  }) async {
    final response = await _http.post(
      _uri(session, '/Sessions/$sessionId/Playing', {
        'playCommand': 'PlayNow',
        'itemIds': itemIds.join(','),
        'startIndex': '$startIndex',
        'startPositionTicks': '${position.inMicroseconds * 10}',
      }),
      headers: _headers(session),
    );
    _ensureSuccess(response);
  }

  Uri webSocketUri(JellyfinSession session) {
    final server = Uri.parse(session.serverUrl);
    return server.replace(
      scheme: server.scheme == 'https' ? 'wss' : 'ws',
      path:
          '${server.path.endsWith('/') ? server.path.substring(0, server.path.length - 1) : server.path}/socket',
      queryParameters: {'ApiKey': session.accessToken},
    );
  }

  Future<List<LyricLine>> fetchLyrics(
    JellyfinSession session,
    String itemId,
  ) async {
    final response = await _http.get(
      _uri(session, '/Audio/$itemId/Lyrics'),
      headers: _headers(session),
    );
    if (response.statusCode == 404 || response.statusCode == 204) {
      return const [];
    }
    final body = _decodeResponse(response);
    return (body['Lyrics'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map((line) {
          final ticks = line['Start'] as int?;
          return LyricLine(
            line['Text'] as String? ?? '',
            ticks == null ? null : Duration(microseconds: ticks ~/ 10),
          );
        })
        .where((line) => line.text.isNotEmpty)
        .toList();
  }

  Uri streamUri(JellyfinSession session, String itemId, {bool small = false}) {
    final query = <String, String>{
      'api_key': session.accessToken,
      'mediaSourceId': itemId,
      'deviceId': session.deviceId,
      if (!small) 'static': 'true',
      if (small) ...{
        'audioCodec': 'aac',
        'audioBitRate': '128000',
        'container': 'm4a',
      },
    };
    return _uri(session, '/Audio/$itemId/stream', query);
  }

  Uri downloadUri(
    JellyfinSession session,
    String itemId, {
    bool small = false,
  }) => small
      ? streamUri(session, itemId, small: true)
      : _uri(session, '/Items/$itemId/Download');

  Map<String, String> downloadHeaders(JellyfinSession session) =>
      _headers(session);

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
    ..._tokenHeaders(session),
    'Authorization': _authorization(
      session.deviceId,
      token: session.accessToken,
    ),
  };

  Map<String, String> _tokenHeaders(JellyfinSession session) => {
    'Accept': 'application/json',
    'X-Emby-Token': session.accessToken,
  };

  String _authorization(String deviceId, {String? token}) {
    final tokenPart = token == null ? '' : ', Token="$token"';
    return 'MediaBrowser Client="$_clientName", Device="$_deviceName", '
        'DeviceId="$deviceId", Version="$_version"$tokenPart';
  }

  String get _deviceName {
    if (kIsWeb) return 'Spotifin Web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Spotifin on Android',
      TargetPlatform.iOS => 'Spotifin on iPhone',
      TargetPlatform.macOS => 'Spotifin on macOS',
      TargetPlatform.windows => 'Spotifin on Windows',
      TargetPlatform.linux => 'Spotifin on Linux',
      TargetPlatform.fuchsia => 'Spotifin',
    };
  }

  Uri _uri(
    JellyfinSession session,
    String path, [
    Map<String, String>? query,
  ]) => Uri.parse('${session.serverUrl}$path').replace(queryParameters: query);

  String _normalizeServerUrl(String value) {
    final trimmed = value.trim();
    final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.host.isEmpty) {
      throw const JellyfinException('Enter a valid Jellyfin address.');
    }
    if (uri.scheme != 'https') {
      throw const JellyfinException('Jellyfin requires an HTTPS address.');
    }
    if (uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const JellyfinException(
        'Enter a Jellyfin server address without credentials or parameters.',
      );
    }
    return uri
        .replace(path: uri.path.replaceFirst(RegExp(r'/+$'), ''))
        .toString();
  }

  Map<String, dynamic> _decodeResponse(
    http.Response response, {
    bool signingIn = false,
  }) {
    _ensureSuccess(response, signingIn: signingIn);
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      throw const JellyfinException('The server returned invalid data.');
    }
  }

  List<dynamic> _decodeResponseList(http.Response response) {
    _ensureSuccess(response);
    try {
      return jsonDecode(response.body) as List<dynamic>;
    } on FormatException {
      throw const JellyfinException('The server returned invalid data.');
    }
  }

  void _ensureSuccess(http.Response response, {bool signingIn = false}) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final message = switch (response.statusCode) {
      401 =>
        signingIn
            ? 'The username or password is incorrect.'
            : 'Jellyfin did not authorize this request.',
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
      container: Value(json['Container'] as String? ?? 'mp3'),
      favorite: Value(userData['IsFavorite'] as bool? ?? false),
      playCount: Value(userData['PlayCount'] as int? ?? 0),
      normalizationGain: Value((json['NormalizationGain'] as num?)?.toDouble()),
      albumNormalizationGain: Value(
        (json['AlbumNormalizationGain'] as num?)?.toDouble(),
      ),
      lastPlayed: Value(
        DateTime.tryParse(userData['LastPlayedDate'] as String? ?? ''),
      ),
      dateCreated: Value(
        DateTime.tryParse(json['DateCreated'] as String? ?? ''),
      ),
      premiereDate: Value(_premiereDate(json)),
    );
  }

  DateTime? _premiereDate(Map<String, dynamic> json) {
    final premiere = DateTime.tryParse(json['PremiereDate'] as String? ?? '');
    if (premiere != null && premiere.year > 1) return premiere;
    final year = json['ProductionYear'] as int?;
    return year == null || year <= 0 ? null : DateTime(year);
  }

  String? _primaryImageTag(Map<String, dynamic> json) {
    final tags = json['ImageTags'] as Map<String, dynamic>?;
    return tags?['Primary'] as String?;
  }
}

class _TimeoutClient extends http.BaseClient {
  _TimeoutClient(this._inner, this._timeout);

  final http.Client _inner;
  final Duration _timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request).timeout(_timeout);
    return http.StreamedResponse(
      response.stream.timeout(_timeout),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();
}
