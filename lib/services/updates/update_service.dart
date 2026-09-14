import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'release_info.dart';

class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

class UpdateService {
  UpdateService({http.Client? httpClient, Duration? requestTimeout})
    : _http = httpClient ?? http.Client(),
      _requestTimeout = requestTimeout ?? const Duration(seconds: 10);

  static final latestReleaseUri = Uri.https(
    'api.github.com',
    '/repos/pablopunk/spotifin/releases/latest',
  );

  final http.Client _http;
  final Duration _requestTimeout;

  void close() => _http.close();

  Future<ReleaseInfo> fetchLatest() async {
    final http.Response response;
    try {
      response = await _http
          .get(
            latestReleaseUri,
            headers: const {'Accept': 'application/vnd.github+json'},
          )
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw const UpdateException('The update check timed out.');
    } catch (error) {
      throw UpdateException('Could not reach GitHub: $error');
    }
    if (response.statusCode != 200) {
      throw UpdateException('GitHub returned ${response.statusCode}.');
    }
    try {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) throw const FormatException();
      return ReleaseInfo.fromGitHub(body);
    } catch (_) {
      throw const UpdateException('GitHub returned an unexpected response.');
    }
  }
}
