import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spotifin/services/downtify/downtify_client.dart';

void main() {
  test('normalizes and requires HTTPS server addresses', () {
    expect(
      DowntifyClient.normalizeServerUrl('downtify.example.com/'),
      'https://downtify.example.com',
    );
    expect(
      () => DowntifyClient.normalizeServerUrl('http://downtify.example.com'),
      throwsA(isA<DowntifyException>()),
    );
    expect(
      () => DowntifyClient.normalizeServerUrl('https://user:pass@example.com'),
      throwsA(isA<DowntifyException>()),
    );
  });

  test('parses live search response fields', () async {
    final client = DowntifyClient(
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode([
            {
              'song_id': 'video-id',
              'name': 'One More Time',
              'artists': ['Daft Punk'],
              'album_name': 'Discovery',
              'cover_url': 'https://images.example.com/cover.jpg',
              'duration': 321,
              'url': 'https://music.youtube.com/watch?v=video-id',
              'explicit': false,
              'year': '',
              'source': 'youtube',
            },
          ]),
          200,
        ),
      ),
    );
    addTearDown(client.close);

    final songs = await client.search(
      'https://downtify.example.com',
      'Daft Punk',
    );

    expect(songs.single.id, 'video-id');
    expect(songs.single.artist, 'Daft Punk');
    expect(songs.single.duration, const Duration(seconds: 321));
    expect(songs.single.sourceUri.host, 'music.youtube.com');
  });

  test('submits one song through the background batch endpoint', () async {
    late http.Request request;
    final client = DowntifyClient(
      httpClient: MockClient((incoming) async {
        request = incoming;
        return http.Response(
          jsonEncode({
            'job_ids': ['video-id'],
            'count': 1,
          }),
          200,
        );
      }),
    );
    addTearDown(client.close);
    final song = (await DowntifyClient(
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode([
            {
              'song_id': 'video-id',
              'name': 'Song',
              'artists': ['Artist'],
            },
          ]),
          200,
        ),
      ),
    ).search('https://example.com', 'Song')).single;

    final jobId = await client.enqueue('https://downtify.example.com', song);

    expect(jobId, 'video-id');
    expect(request.url.path, '/api/download/batch');
    expect(jsonDecode(request.body), {
      'songs': [song.raw],
      'playlist_url': '',
      'generate_m3u': false,
    });
  });

  test('parses queue progress and errors', () async {
    final client = DowntifyClient(
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode([
            {
              'song': {
                'song_id': 'one',
                'name': 'Song',
                'artists': ['Artist'],
              },
              'status': 'downloading',
              'progress': 42.5,
              'message': 'Downloading',
              'filename': null,
            },
          ]),
          200,
        ),
      ),
    );
    addTearDown(client.close);

    final jobs = await client.fetchQueue('https://downtify.example.com');

    expect(jobs.single.song.id, 'one');
    expect(jobs.single.progress, 42.5);
    expect(jobs.single.message, 'Downloading');
  });
}
