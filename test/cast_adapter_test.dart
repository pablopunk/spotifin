import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/services/cast/jellyfin_cast_adapter.dart';

void main() {
  test('pins Jellyfin receiver app IDs with stable default', () {
    expect(JellyfinCastAdapter.stableReceiverAppId, 'F007D354');
    expect(JellyfinCastAdapter.unstableReceiverAppId, '6F511C87');
    expect(JellyfinCastAdapter.receiverAppId(), 'F007D354');
    expect(JellyfinCastAdapter.receiverAppId(unstable: true), '6F511C87');
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
}
