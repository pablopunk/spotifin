import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spotifin/platform/artwork_store.dart';
import 'package:spotifin/platform/download_store.dart';
import 'package:spotifin/services/downloads/download_service.dart';
import 'package:spotifin/services/jellyfin/jellyfin_client.dart';
import 'package:spotifin/services/jellyfin/session.dart';
import 'package:spotifin/storage/database.dart';

void main() {
  test('remove() during a save leaves no failed row', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final client = JellyfinClient(
      httpClient: MockClient((_) async => http.Response('', 204)),
    );
    final store = _BlockingStore();
    final service = DownloadService(database, client, store, _FakeArtwork());
    addTearDown(() async {
      service.dispose();
      client.close();
      await database.close();
    });
    await database.upsertTracks([
      TracksCompanion.insert(id: 'track', name: 'Song'),
    ]);
    final track = (await database.allTracks()).single;

    await service.download(session, track);
    await store.saveStarted.future;

    await service.remove(track.id);
    store.saveResult.completeError(
      const DownloadStoreException('gone', statusCode: 404),
    );
    await _waitForIdle(service, track.id);

    final downloads = await database.allDownloads();
    expect(downloads.where((row) => row.status == 'failed'), isEmpty);
  });

  test('suspend() during a save re-queues and never fails', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final client = JellyfinClient(
      httpClient: MockClient((_) async => http.Response('', 204)),
    );
    final store = _BlockingStore();
    final service = DownloadService(database, client, store, _FakeArtwork());
    addTearDown(() async {
      service.dispose();
      client.close();
      await database.close();
    });
    await database.upsertTracks([
      TracksCompanion.insert(id: 'track', name: 'Song'),
    ]);
    final track = (await database.allTracks()).single;

    await service.download(session, track);
    await store.saveStarted.future;

    final suspending = service.suspend();
    store.saveResult.completeError(
      const DownloadStoreException('gone', statusCode: 404),
    );
    await suspending;

    final row = (await database.allDownloads()).single;
    expect(row.status, 'queued');
  });
}

Future<void> _waitForIdle(DownloadService service, String trackId) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (service.isActive(trackId) && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

const session = JellyfinSession(
  serverUrl: 'https://jellyfin.example.com',
  serverId: 'server',
  deviceId: 'device',
  userId: 'user',
  userName: 'Pablo',
  accessToken: 'token',
);

class _BlockingStore implements DownloadStore {
  final saveStarted = Completer<void>();
  final saveResult = Completer<String>();

  @override
  Future<String> save(
    String accountId,
    String trackId,
    Uri source,
    Map<String, String> headers,
    String extension,
  ) {
    if (!saveStarted.isCompleted) saveStarted.complete();
    return saveResult.future;
  }

  @override
  Future<Uri?> resolve(String storedUri) async => null;

  @override
  Future<void> remove(String storedUri) async {}

  @override
  void dispose() {}
}

class _FakeArtwork implements ArtworkStore {
  @override
  Future<ImageProvider?> resolve(
    String accountId,
    String itemId,
    int width,
    Uri source,
  ) async => null;

  @override
  void dispose() {}
}
