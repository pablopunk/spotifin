import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/app/state/app_controller.dart';
import 'package:spotifin/features/downtify/downtify_settings_screen.dart';
import 'package:spotifin/features/downtify/external_track_tile.dart';
import 'package:spotifin/services/downtify/downtify_client.dart';
import 'package:spotifin/services/jellyfin/session.dart';
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

  testWidgets('shows queued songs and can stop a download', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({
      'downtifyServerUrl': 'https://downtify.example.com',
    });
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final now = DateTime(2026);
    await database.putDowntifyImport(
      DowntifyImportsCompanion.insert(
        id: 'server:user:song',
        jellyfinServerId: 'server',
        jellyfinUserId: 'user',
        downtifyUrl: 'https://downtify.example.com',
        externalSongId: 'song',
        songJson: jsonEncode({
          'song_id': 'song',
          'name': 'Queued Song',
          'artists': ['Artist'],
        }),
        status: 'queued',
        createdAt: now,
        updatedAt: now,
      ),
    );
    final client = DowntifyClient(
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/version') {
          return http.Response(jsonEncode('2.10.2'), 200);
        }
        if (request.method == 'DELETE') {
          return http.Response('{"removed":true}', 200);
        }
        return http.Response('[]', 200);
      }),
    );
    addTearDown(client.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          downtifyClientProvider.overrideWithValue(client),
          appControllerProvider.overrideWith(_AuthenticatedAppController.new),
        ],
        child: const MaterialApp(home: DowntifySettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DOWNLOAD QUEUE'), findsOneWidget);
    expect(find.text('Queued Song'), findsOneWidget);
    await tester.tap(find.byTooltip('Stop download'));
    await tester.pumpAndSettle();
    expect(find.text('Queued Song'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(database.close);
  });
}

class _AuthenticatedAppController extends AppController {
  @override
  AppState build() => const AppState(
    status: AppStatus.ready,
    session: JellyfinSession(
      serverUrl: 'https://jellyfin.example.com',
      serverId: 'server',
      deviceId: 'device',
      userId: 'user',
      userName: 'Pablo',
      accessToken: 'token',
    ),
  );
}
