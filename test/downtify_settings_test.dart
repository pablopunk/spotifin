import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/features/downtify/downtify_settings_screen.dart';
import 'package:spotifin/features/downtify/external_track_tile.dart';
import 'package:spotifin/services/downtify/downtify_client.dart';
import 'package:spotifin/storage/database.dart';

void main() {
  testWidgets('configures HTTPS Downtify and enables dedicated search', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final database = AppDatabase.forTesting(NativeDatabase.memory());
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
              'song_id': 'song',
              'name': 'Song',
              'artists': ['Artist'],
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
        child: const MaterialApp(home: DowntifySettingsScreen()),
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.byType(TextField).first,
      'downtify.example.com',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save and test'));
    await tester.pumpAndSettle();

    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Downtify 2.10.2'), findsOneWidget);
    expect(find.text('SEARCH DOWNTIFY'), findsOneWidget);

    await tester.enterText(find.byType(SearchBar), 'Song');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();

    expect(find.byType(ExternalTrackTile), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });
}
