import 'dart:convert';

import 'package:http/http.dart' as http;

import 'downtify_models.dart';

class DowntifyException implements Exception {
  const DowntifyException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class DowntifyClient {
  DowntifyClient({
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 8),
  }) : _http = httpClient ?? http.Client();

  final http.Client _http;
  final Duration timeout;

  void close() => _http.close();

  static String normalizeServerUrl(String value) {
    final trimmed = value.trim();
    final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty) {
      throw const DowntifyException('Enter a valid Downtify address.');
    }
    if (uri.scheme != 'https') {
      throw const DowntifyException('Downtify requires an HTTPS address.');
    }
    if (uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const DowntifyException(
        'Enter a Downtify server address without credentials or parameters.',
      );
    }
    return uri
        .replace(path: uri.path.replaceFirst(RegExp(r'/+$'), ''))
        .toString();
  }

  Future<String> fetchVersion(String serverUrl) async {
    final response = await _get(_uri(serverUrl, '/api/version'));
    final decoded = _decode(response);
    if (decoded is! String || decoded.isEmpty) {
      throw const DowntifyException('Downtify returned an invalid version.');
    }
    return decoded;
  }

  Future<List<DowntifySong>> search(String serverUrl, String query) async {
    final response = await _get(
      _uri(serverUrl, '/api/songs/search', {'query': query.trim()}),
    );
    final decoded = _decode(response);
    if (decoded is! List<dynamic>) {
      throw const DowntifyException(
        'Downtify returned invalid search results.',
      );
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(DowntifySong.fromJson)
        .toList(growable: false);
  }

  Future<String> enqueue(String serverUrl, DowntifySong song) async {
    final response = await _http
        .post(
          _uri(serverUrl, '/api/download/batch'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'songs': [song.raw],
            'playlist_url': '',
            'generate_m3u': false,
          }),
        )
        .timeout(timeout);
    final decoded = _decode(response);
    if (decoded is! Map<String, dynamic>) {
      throw const DowntifyException(
        'Downtify returned an invalid download response.',
      );
    }
    final ids = decoded['job_ids'];
    if (ids is! List<dynamic> || ids.isEmpty || ids.first is! String) {
      throw const DowntifyException('Downtify did not return a download job.');
    }
    return ids.first as String;
  }

  Future<List<DowntifyJob>> fetchQueue(String serverUrl) async {
    final response = await _get(_uri(serverUrl, '/api/queue'));
    final decoded = _decode(response);
    if (decoded is! List<dynamic>) {
      throw const DowntifyException('Downtify returned an invalid queue.');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(DowntifyJob.fromJson)
        .toList(growable: false);
  }

  Future<http.Response> _get(Uri uri) => _http.get(uri).timeout(timeout);

  Uri _uri(String serverUrl, String path, [Map<String, String>? query]) {
    final base = Uri.parse(normalizeServerUrl(serverUrl));
    return base.replace(path: '${base.path}$path', queryParameters: query);
  }

  Object? _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DowntifyException(
        'Downtify request failed (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    if (response.bodyBytes.length > 2 * 1024 * 1024) {
      throw const DowntifyException('Downtify returned too much data.');
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const DowntifyException('Downtify returned invalid data.');
    }
  }
}
