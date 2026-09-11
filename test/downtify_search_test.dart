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
import 'package:spotifin/features/downtify/external_track_tile.dart';
import 'package:spotifin/features/home/home_screen.dart';
import 'package:spotifin/services/downtify/downtify_client.dart';
import 'package:spotifin/storage/database.dart';

void main() {
  testWidgets('merges Downtify results and hides duplicates only in All', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'downtifyServerUrl': 'https://downtify.example.com',
    });
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.upsertTracks([
      TracksCompanion.insert(
        id: 'local',
        name: 'One More Time',
        artist: const Value('Daft Punk'),
      ),
    ]);
    final client = DowntifyClient(
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/version') {
          return http.Response(jsonEncode('2.10.2'), 200);
        }
        if (request.url.path == '/api/queue') {
          return http.Response('[]', 200);
        }
        return http.Response(
          jsonEncode([
            {
              'song_id': 'duplicate',
              'name': 'One More Time',
              'artists': ['Daft Punk'],
            },
            {
              'song_id': 'external',
              'name': 'One More Time Again',
              'artists': ['Daft Punk'],
            },
          ]),
          200,
        );
      }),
    );
    addTearDown(client.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          downtifyClientProvider.overrideWithValue(client),
        ],
        child: const MaterialApp(home: Scaffold(body: HomeScreen())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(SearchBar), 'One More Time');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.byType(ExternalTrackTile), findsOneWidget);

    await tester.tap(find.widgetWithText(Tab, 'Downtify'));
    await tester.pump();

    expect(find.byType(ExternalTrackTile), findsNWidgets(2));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });
}
