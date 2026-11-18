import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/features/downtify/downtify_collection_tab.dart';
import 'package:spotifin/features/downtify/external_track_tile.dart';
import 'package:spotifin/features/library/library_screen.dart';
import 'package:spotifin/services/downtify/downtify_client.dart';
import 'package:spotifin/services/downtify/downtify_models.dart';
import 'package:spotifin/storage/database.dart';

DowntifySong _song(String id, String artist, String album) =>
    DowntifySong.fromJson({
      'song_id': id,
      'name': id,
      'artists': [artist],
      'album_name': album,
    });

void main() {
  test('album search keeps the artist and lists the album first', () {
    const search = DowntifyCollectionSearch.album(
      album: 'OK Computer',
      artist: 'Radiohead',
    );
    final songs = search.filter([
      _song('creep', 'Radiohead', 'Pablo Honey'),
      _song('cover', 'Vitamin String Quartet', 'OK Computer'),
      _song('airbag', 'radiohead', 'OK Computer'),
    ]);

    expect(search.query, 'Radiohead OK Computer');
    expect(songs.map((song) => song.id), ['airbag', 'creep']);
  });

  for (final kind in [CollectionKind.artist, CollectionKind.album]) {
    testWidgets('${kind.name} page shows a Downtify tab', (tester) async {
      SharedPreferences.setMockInitialValues({
        'downtifyServerUrl': 'https://downtify.example.com',
      });
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      final queries = <String>[];
      final client = DowntifyClient(
        httpClient: MockClient((request) async {
          if (request.url.path == '/api/version') {
            return http.Response(jsonEncode('2.12.0'), 200);
          }
          if (request.url.path == '/api/queue') {
            return http.Response('[]', 200);
          }
          queries.add(request.url.queryParameters['query']!);
          return http.Response(
            jsonEncode([
              {
                'song_id': 'external',
                'name': 'Aerodynamic',
                'artists': ['Daft Punk'],
              },
              {
                'song_id': 'other',
                'name': 'Cover',
                'artists': ['Someone Else'],
              },
            ]),
            200,
          );
        }),
      );
      addTearDown(client.close);
      final track = Track(
        id: 'local',
        name: 'One More Time',
        artist: 'Daft Punk',
        album: 'Discovery',
        artistItems: '[]',
        labels: '[]',
        durationTicks: 0,
        favorite: false,
        playCount: 0,
        container: 'mp3',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            downtifyClientProvider.overrideWithValue(client),
          ],
          child: MaterialApp(
            home: CollectionScreen(
              title: kind == CollectionKind.artist ? 'Daft Punk' : 'Discovery',
              tracks: [track],
              kind: kind,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Downtify'));
      await tester.pumpAndSettle();

      expect(queries, [
        kind == CollectionKind.artist ? 'Daft Punk' : 'Daft Punk Discovery',
      ]);
      expect(find.byType(ExternalTrackTile), findsOneWidget);
      expect(find.text('Aerodynamic'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await tester.runAsync(database.close);
    });
  }
}
