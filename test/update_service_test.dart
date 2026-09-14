import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spotifin/services/updates/update_service.dart';

void main() {
  test('parses the latest GitHub release', () async {
    late http.Request request;
    final service = UpdateService(
      httpClient: MockClient((incoming) async {
        request = incoming;
        return http.Response(
          jsonEncode({
            'tag_name': 'v0.2.0',
            'name': 'v0.2.0 - Tuned up',
            'html_url':
                'https://github.com/pablopunk/spotifin/releases/tag/v0.2.0',
            'published_at': '2026-09-01T10:00:00Z',
          }),
          200,
        );
      }),
    );
    addTearDown(service.close);

    final release = await service.fetchLatest();

    expect(
      request.url.toString(),
      'https://api.github.com/repos/pablopunk/spotifin/releases/latest',
    );
    expect(request.headers['Accept'], 'application/vnd.github+json');
    expect(release.version, '0.2.0');
    expect(release.name, 'v0.2.0 - Tuned up');
    expect(release.url, contains('/releases/tag/v0.2.0'));
    expect(release.publishedAt, DateTime.utc(2026, 9, 1, 10));
  });

  test('reports an HTTP error', () async {
    final service = UpdateService(
      httpClient: MockClient((_) async => http.Response('rate limited', 403)),
    );
    addTearDown(service.close);

    await expectLater(service.fetchLatest(), throwsA(isA<UpdateException>()));
  });

  test('reports malformed JSON', () async {
    final service = UpdateService(
      httpClient: MockClient((_) async => http.Response('not json', 200)),
    );
    addTearDown(service.close);

    await expectLater(service.fetchLatest(), throwsA(isA<UpdateException>()));
  });

  test('reports a release without a tag', () async {
    final service = UpdateService(
      httpClient: MockClient(
        (_) async =>
            http.Response(jsonEncode({'html_url': 'https://example.com'}), 200),
      ),
    );
    addTearDown(service.close);

    await expectLater(service.fetchLatest(), throwsA(isA<UpdateException>()));
  });
}
