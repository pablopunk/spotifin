import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:spotifin/services/cast/jellyfin_receiver_protocol.dart';
import 'package:spotifin/services/jellyfin/session.dart';

const _session = JellyfinSession(
  serverUrl: 'https://music.example.com/jellyfin/',
  serverId: 'server',
  deviceId: 'phone',
  userId: 'user',
  userName: 'Pablo',
  accessToken: 'token',
);

void main() {
  test('PlayNow carries items, start index, position and credentials', () {
    final message = JellyfinReceiverProtocol.playNow(
      _session,
      itemIds: ['a', 'b'],
      startIndex: 1,
      startPosition: const Duration(seconds: 12),
    );

    expect(message['command'], 'PlayNow');
    expect(message['serverAddress'], 'https://music.example.com/jellyfin');
    expect(message['accessToken'], 'token');
    expect(message['userId'], 'user');
    expect(message['serverId'], 'server');
    final options = message['options']! as Map<String, Object?>;
    expect(options['startIndex'], 1);
    expect(options['startPositionTicks'], 120000000);
    expect(options['items'], [
      {
        'Id': 'a',
        'ServerId': 'server',
        'Type': 'Audio',
        'MediaType': 'Audio',
        'IsFolder': false,
      },
      {
        'Id': 'b',
        'ServerId': 'server',
        'Type': 'Audio',
        'MediaType': 'Audio',
        'IsFolder': false,
      },
    ]);
  });

  test('PlayNow from the start omits the position', () {
    final options =
        JellyfinReceiverProtocol.playNow(
              _session,
              itemIds: ['a'],
              startIndex: 0,
              startPosition: Duration.zero,
            )['options']!
            as Map<String, Object?>;
    expect(options.containsKey('startPositionTicks'), isFalse);
  });

  test('seek is in seconds and repeat uses Jellyfin modes', () {
    expect(
      JellyfinReceiverProtocol.seek(
        _session,
        const Duration(milliseconds: 1500),
      )['options'],
      {'position': 1.5},
    );
    expect(
      JellyfinReceiverProtocol.setRepeatMode(_session, LoopMode.one)['options'],
      {'RepeatMode': 'RepeatOne'},
    );
  });

  test('receiver error messages become user-visible text', () {
    expect(
      JellyfinReceiverProtocol.errorFromReceiverMessage(
        '{"type":"playbackerror","message":"NoCompatibleStream"}',
      ),
      contains('can’t play on Chromecast'),
    );
    expect(
      JellyfinReceiverProtocol.errorFromReceiverMessage(
        '{"type":"connectionerror"}',
      ),
      contains('could not reach your Jellyfin server'),
    );
    expect(
      JellyfinReceiverProtocol.errorFromReceiverMessage(
        '{"type":"playbackprogress"}',
      ),
      isNull,
    );
    expect(JellyfinReceiverProtocol.errorFromReceiverMessage('nope'), isNull);
  });
}
