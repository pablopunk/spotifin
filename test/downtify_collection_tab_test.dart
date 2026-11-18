import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/features/downtify/external_track_tile.dart';
import 'package:spotifin/features/library/library_screen.dart';
import 'package:spotifin/services/downtify/downtify_client.dart';
import 'package:spotifin/storage/database.dart';

Map<String, Object> _song(String id, String name, String artist) => {
  'song_id': id,
  'name': name,
  'artists': [artist],
};

const _responses = <String, Object>{
  '/api/artists/search': [
    {'artist_id': 'daft', 'name': 'Daft Punk'},
  ],
  '/api/albums/search': [
    {
      'name': 'Discovery',
      'artists': ['Daft Punk'],
      'url': 'https://music.youtube.com/browse/discovery',
    },
  ],
};

Object _respond(Uri url) => switch (url.path) {
  '/api/artists/top_songs' => [_song('top', 'Around the World', 'Daft Punk')],
  '/api/songs/search' => [
    _song('search', 'Aerodynamic', 'Daft Punk'),
    _song('repeat', 'Around the World', 'Daft Punk'),
    _song('other', 'Cover', 'Someone Else'),
  ],
  '/api/url' => [
    _song('one', 'Digital Love', 'Daft Punk'),
    _song('two', 'Voyager', 'Daft Punk'),
  ],
  final path => _responses[path] ?? [],
};

Future<List<String>> _showDowntifyTab(
  WidgetTester tester,
  CollectionKind kind,
) async {
  SharedPreferences.setMockInitialValues({
    'downtifyServerUrl': 'https://downtify.example.com',
  });
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  final client = DowntifyClient(
    httpClient: MockClient((request) async {
      if (request.url.path == '/api/version') {
        return http.Response(jsonEncode('2.12.0'), 200);
      }
      return http.Response(jsonEncode(_respond(request.url)), 200);
    }),
  );
  addTearDown(client.close);
  const track = Track(
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
          tracks: const [track],
          kind: kind,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(Tab, 'Downtify'));
  await tester.pumpAndSettle();

  final titles = tester
      .widgetList<ExternalTrackTile>(find.byType(ExternalTrackTile))
      .map((tile) => tile.song.name)
      .toList();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
  await tester.runAsync(database.close);
  return titles;
}

void main() {
  testWidgets('artist tab lists top songs before search results', (
    tester,
  ) async {
    expect(await _showDowntifyTab(tester, CollectionKind.artist), [
      'Around the World',
      'Aerodynamic',
    ]);
  });

  testWidgets('album tab lists the full album tracklist', (tester) async {
    expect(await _showDowntifyTab(tester, CollectionKind.album), [
      'Digital Love',
      'Voyager',
    ]);
  });
}
