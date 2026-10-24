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
    expect(store.cancelledTracks, contains(track.id));
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

    await expectLater(
      service.suspend().timeout(const Duration(seconds: 2)),
      completes,
    );
    expect(store.cancelAllCalls, 1);

    final row = (await database.allDownloads()).single;
    expect(row.status, 'queued');
  });

  test('clear() cancels active saves before removing download rows', () async {
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

    await expectLater(
      service.clear().timeout(const Duration(seconds: 2)),
      completes,
    );
    expect(store.cancelAllCalls, 1);
    expect(await database.allDownloads(), isEmpty);
  });

  test('reconcile() cancels active orphaned saves', () async {
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

    await service.reconcile(const []);

    expect(store.cancelledTracks, contains(track.id));
    expect(await database.allDownloads(), isEmpty);
  });

  test('dispose() cancels outstanding saves', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final client = JellyfinClient(
      httpClient: MockClient((_) async => http.Response('', 204)),
    );
    final store = _BlockingStore();
    final service = DownloadService(database, client, store, _FakeArtwork());
    var serviceDisposed = false;
    addTearDown(() async {
      if (!serviceDisposed) service.dispose();
      client.close();
      await database.close();
    });
    await database.upsertTracks([
      TracksCompanion.insert(id: 'track', name: 'Song'),
    ]);
    final track = (await database.allTracks()).single;

    await service.download(session, track);
    await store.saveStarted.future;

    service.dispose();
    serviceDisposed = true;
    await expectLater(
      store.saveResult.future,
      throwsA(isA<DownloadStoreException>()),
    );
    expect(store.disposed, isTrue);
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
  final cancelledTracks = <String>[];
  var cancelAllCalls = 0;
  var disposed = false;

  @override
  Future<String> save(
    String accountId,
    String trackId,
    Uri source,
    Map<String, String> headers,
    String extension, {
    Duration timeout = const Duration(minutes: 5),
  }) {
    if (!saveStarted.isCompleted) saveStarted.complete();
    return saveResult.future;
  }

  @override
  Future<Uri?> resolve(String storedUri) async => null;

  @override
  Future<void> remove(String storedUri) async {}

  @override
  Future<void> cancel(String accountId, String trackId) async {
    cancelledTracks.add(trackId);
    _finishCancelled();
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCalls++;
    _finishCancelled();
  }

  @override
  void dispose() {
    disposed = true;
    _finishCancelled();
  }

  void _finishCancelled() {
    if (!saveResult.isCompleted) {
      saveResult.completeError(
        const DownloadStoreException('Download cancelled.'),
      );
    }
  }
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
