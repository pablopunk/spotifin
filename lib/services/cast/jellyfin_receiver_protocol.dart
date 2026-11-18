import 'dart:convert';

import 'package:just_audio/just_audio.dart' show LoopMode;

import '../jellyfin/session.dart';

/// Messages for the Jellyfin Cast receiver's own command channel.
///
/// This is the protocol jellyfin-web's Chromecast player speaks: the sender
/// hands the receiver a list of item ids plus credentials, and the receiver
/// fetches playback info, owns the queue, advances on its own when a track
/// ends, and reports playback to the server. The phone is only a remote, so
/// playback survives the phone sleeping or the app being killed.
abstract final class JellyfinReceiverProtocol {
  static const namespace = 'urn:x-cast:com.connectsdk';

  /// Cast messages are capped at 64 KiB; each item stub is ~130 bytes.
  static const maxItemsPerMessage = 300;

  static Map<String, Object?> playNow(
    JellyfinSession session, {
    required List<String> itemIds,
    required int startIndex,
    required Duration startPosition,
  }) => _command(session, 'PlayNow', {
    'items': _itemStubs(session, itemIds),
    'startIndex': startIndex,
    if (startPosition > Duration.zero)
      'startPositionTicks': _ticks(startPosition),
  });

  static Map<String, Object?> playLast(
    JellyfinSession session, {
    required List<String> itemIds,
  }) => _command(session, 'PlayLast', {'items': _itemStubs(session, itemIds)});

  static Map<String, Object?> nextTrack(JellyfinSession session) =>
      _command(session, 'NextTrack', const {});

  static Map<String, Object?> seek(
    JellyfinSession session,
    Duration position,
  ) => _command(session, 'Seek', {
    'position': position.inMilliseconds / Duration.millisecondsPerSecond,
  });

  static Map<String, Object?> setRepeatMode(
    JellyfinSession session,
    LoopMode mode,
  ) => _command(session, 'SetRepeatMode', {
    'RepeatMode': switch (mode) {
      LoopMode.off => 'RepeatNone',
      LoopMode.all => 'RepeatAll',
      LoopMode.one => 'RepeatOne',
    },
  });

  static Map<String, Object?> _command(
    JellyfinSession session,
    String command,
    Map<String, Object?> options,
  ) => {
    'command': command,
    'options': options,
    'serverAddress': _serverAddress(session.serverUrl),
    'serverId': session.serverId,
    'userId': session.userId,
    'accessToken': session.accessToken,
    'deviceId': session.deviceId,
  };

  static List<Map<String, Object?>> _itemStubs(
    JellyfinSession session,
    List<String> itemIds,
  ) => [
    for (final id in itemIds)
      {
        'Id': id,
        'ServerId': session.serverId,
        'Type': 'Audio',
        'MediaType': 'Audio',
        'IsFolder': false,
      },
  ];

  static int _ticks(Duration position) => position.inMicroseconds * 10;

  static String _serverAddress(String serverUrl) => serverUrl.endsWith('/')
      ? serverUrl.substring(0, serverUrl.length - 1)
      : serverUrl;

  /// User-visible error carried by a receiver bus message, if any.
  ///
  /// The receiver reports `playbackerror` (with a Jellyfin error code such as
  /// `NoCompatibleStream`) and `connectionerror` (server unreachable).
  static String? errorFromReceiverMessage(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    return switch (decoded['type']) {
      'connectionerror' =>
        'Chromecast could not reach your Jellyfin server. Check that the '
            'server address works on your Wi-Fi network.',
      'playbackerror' => _playbackErrorMessage(decoded['message']),
      _ => null,
    };
  }

  static String _playbackErrorMessage(Object? code) => switch (code) {
    'NoCompatibleStream' => 'This track can’t play on Chromecast.',
    'NotAllowed' => 'Your Jellyfin account can’t play this on Chromecast.',
    _ => 'Chromecast could not play this track.',
  };
}
