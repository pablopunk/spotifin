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
  test('persisted download failures redact credentials', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final client = JellyfinClient(
      httpClient: MockClient((_) async => http.Response('', 204)),
    );
    final store = _FakeStore(
      () async => throw const DownloadStoreException(
        'Failed: https://x/Audio/1/stream?api_key=SECRET',
        statusCode: 404,
      ),
    );
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

    Download? row;
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (DateTime.now().isBefore(deadline)) {
      row = (await database.allDownloads()).firstOrNull;
      if (row?.status == 'failed') break;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(row?.status, 'failed');
    expect(row!.error, isNotNull);
    expect(row.error, isNot(contains('SECRET')));
  });
}

const session = JellyfinSession(
  serverUrl: 'https://jellyfin.example.com',
  serverId: 'server',
  deviceId: 'device',
  userId: 'user',
  userName: 'Pablo',
  accessToken: 'token',
);

class _FakeStore implements DownloadStore {
  _FakeStore(this.onSave);

  final Future<String> Function() onSave;

  @override
  Future<String> save(
    String accountId,
    String trackId,
    Uri source,
    Map<String, String> headers,
    String extension,
  ) => onSave();

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
