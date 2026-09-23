import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/services/cast/jellyfin_cast_adapter.dart';
import 'package:spotifin/services/jellyfin/jellyfin_client.dart';
import 'package:spotifin/services/jellyfin/session.dart';
import 'package:spotifin/storage/database.dart';

Track track({
  String id = 'track-1',
  String container = 'mp3',
  int durationTicks = 1800000000,
}) => Track(
  id: id,
  name: 'Song $id',
  album: 'Album',
  albumId: 'album-1',
  artist: 'Artist',
  artistItems: '[]',
  labels: '[]',
  durationTicks: durationTicks,
  container: container,
  favorite: false,
  playCount: 0,
);

const session = JellyfinSession(
  serverUrl: 'https://example.com/jellyfin',
  serverId: 'server',
  deviceId: 'phone',
  userId: 'user',
  userName: 'Pablo',
  accessToken: 'token',
);

JellyfinCastAdapter adapter() => JellyfinCastAdapter(JellyfinClient());

void main() {
  test('pins Jellyfin receiver app IDs with stable default', () {
    expect(JellyfinCastAdapter.stableReceiverAppId, 'F007D354');
    expect(JellyfinCastAdapter.unstableReceiverAppId, '6F511C87');
    expect(JellyfinCastAdapter.receiverAppId(), 'F007D354');
    expect(JellyfinCastAdapter.receiverAppId(unstable: true), '6F511C87');
  });

  test('maps containers to audio MIME types', () {
    expect(JellyfinCastAdapter.contentTypeForContainer('mp3'), 'audio/mpeg');
    expect(JellyfinCastAdapter.contentTypeForContainer('FLAC'), 'audio/flac');
    expect(JellyfinCastAdapter.contentTypeForContainer('m4a'), 'audio/mp4');
    expect(JellyfinCastAdapter.contentTypeForContainer('aac'), 'audio/aac');
    expect(JellyfinCastAdapter.contentTypeForContainer('wav'), 'audio/wav');
    expect(JellyfinCastAdapter.contentTypeForContainer('ogg'), 'audio/ogg');
    expect(JellyfinCastAdapter.contentTypeForContainer('opus'), 'audio/opus');
    expect(JellyfinCastAdapter.contentTypeForContainer('exotic'), 'audio/mpeg');
  });

  test('rejects plain-http and local servers for Cast', () {
    expect(
      JellyfinCastAdapter.isServerReachableByCast(
        Uri.parse('https://music.example.com/jellyfin'),
      ),
      isTrue,
    );
    expect(
      JellyfinCastAdapter.isServerReachableByCast(
        Uri.parse('http://192.168.1.10:8096'),
      ),
      isFalse,
    );
    expect(
      JellyfinCastAdapter.isServerReachableByCast(
        Uri.parse('https://localhost:8096'),
      ),
      isFalse,
    );
    expect(
      JellyfinCastAdapter.serverBlockerMessage(
        Uri.parse('http://192.168.1.10:8096'),
      ),
      contains('plain HTTP'),
    );
  });

  test('builds handoff payload with metadata and clamped position', () {
    final payload = adapter().buildPayload(
      session,
      track(),
      position: const Duration(seconds: 42),
    );

    expect(payload.contentId, 'track-1');
    expect(payload.contentType, 'audio/mpeg');
    expect(payload.title, 'Song track-1');
    expect(payload.artist, 'Artist');
    expect(payload.album, 'Album');
    expect(payload.startPosition, const Duration(seconds: 42));
    expect(payload.duration, const Duration(minutes: 3));
    expect(payload.itemId, 'track-1');
    // Opaque ids only: never credentials.
    expect(payload.customData, {'itemId': 'track-1'});
    expect(payload.contentUrl.toString(), contains('/Audio/track-1/stream'));
    expect(payload.artworkUrl.toString(), contains('/Items/album-1/Images'));
  });

  test('clamps handoff position to track duration', () {
    final payload = adapter().buildPayload(
      session,
      track(durationTicks: 600000000),
      position: const Duration(minutes: 10),
    );

    expect(payload.duration, const Duration(seconds: 60));
    expect(payload.startPosition, const Duration(seconds: 60));
  });

  test('small profile uses the AAC fallback content type', () {
    final payload = adapter().buildPayload(
      session,
      track(container: 'flac'),
      position: Duration.zero,
      small: true,
    );

    expect(payload.contentType, 'audio/mp4');
    expect(payload.contentUrl.queryParameters['audioCodec'], 'aac');
  });
}
