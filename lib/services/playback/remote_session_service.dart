import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/status.dart' as socket_status;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../storage/database.dart';
import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/remote_session.dart';
import '../jellyfin/session.dart';
import '../redaction.dart';
import 'playback_handoff.dart';
import 'playback_service.dart';
import 'remote_command_handler.dart';

class RemoteSessionService extends ChangeNotifier {
  RemoteSessionService(
    this._client,
    PlaybackService playback,
    AppDatabase database,
  ) : _commands = RemoteCommandHandler(playback, database),
      _handoff = PlaybackHandoff(_client, playback, database);

  final JellyfinClient _client;
  final RemoteCommandHandler _commands;
  final PlaybackHandoff _handoff;
  JellyfinSession? _session;
  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _socketSubscription;
  Timer? _pollTimer;
  Timer? _keepAliveTimer;
  Timer? _reconnectTimer;
  Future<void> _commandQueue = Future.value();
  List<RemoteSession> _sessions = const [];
  Set<String> _pendingSessionIds = const {};
  bool _connected = false;
  bool _loading = false;
  String? _error;
  int _generation = 0;
  int _reconnectAttempt = 0;

  List<RemoteSession> get sessions => _sessions;
  Set<String> get pendingSessionIds => _pendingSessionIds;
  bool get connected => _connected;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> configure(JellyfinSession session) async {
    await clear();
    _session = session;
    final generation = ++_generation;
    _loading = true;
    notifyListeners();
    try {
      try {
        await _client.advertiseRemoteCapabilities(session);
      } catch (error) {
        _error = redactSecrets(error);
      }
      await refresh();
      if (generation != _generation) return;
      unawaited(_connect(generation));
      _pollTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => unawaited(refresh()),
      );
    } catch (error) {
      if (generation != _generation) return;
      _error = redactSecrets(error);
    } finally {
      if (generation == _generation) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refresh() async {
    final session = _session;
    if (session == null) return;
    try {
      _sessions = await _client.fetchSessions(session);
      _error = null;
      notifyListeners();
    } catch (error) {
      _error = redactSecrets(error);
      notifyListeners();
    }
  }

  Future<void> pause(RemoteSession target) => _sendPlaystate(target, 'Pause');

  Future<void> play(RemoteSession target) => _sendPlaystate(target, 'Unpause');

  Future<void> stop(RemoteSession target) => _sendPlaystate(target, 'Stop');

  Future<void> next(RemoteSession target) =>
      _sendPlaystate(target, 'NextTrack');

  Future<void> previous(RemoteSession target) =>
      _sendPlaystate(target, 'PreviousTrack');

  Future<void> seek(RemoteSession target, Duration position) =>
      _sendPlaystate(target, 'Seek', position: position);

  Future<void> setVolume(RemoteSession target, int volume) =>
      _sendGeneral(target, 'SetVolume', {'Volume': '${volume.clamp(0, 100)}'});

  Future<void> setShuffle(RemoteSession target, bool enabled) => _sendGeneral(
    target,
    'SetShuffleQueue',
    {'ShuffleMode': enabled ? 'Shuffle' : 'Sorted'},
  );

  Future<void> setRepeatMode(RemoteSession target, String mode) =>
      _sendGeneral(target, 'SetRepeatMode', {'RepeatMode': mode});

  Future<void> takeOver(RemoteSession source) =>
      _withPending(source.id, () async {
        final session = _session;
        if (session == null) return;
        _sessions = await _handoff.takeOver(session, source);
        notifyListeners();
      });

  Future<void> _sendPlaystate(
    RemoteSession target,
    String command, {
    Duration? position,
  }) => _withPending(target.id, () async {
    final session = _session;
    if (session == null) return;
    await _client.sendPlaystateCommand(
      session,
      target.id,
      command,
      position: position,
    );
    await refresh();
  });

  Future<void> _sendGeneral(
    RemoteSession target,
    String name,
    Map<String, String> arguments,
  ) => _withPending(target.id, () async {
    final session = _session;
    if (session == null) return;
    await _client.sendGeneralCommand(session, target.id, name, arguments);
    await refresh();
  });

  Future<void> _withPending(
    String sessionId,
    Future<void> Function() action,
  ) async {
    _pendingSessionIds = {..._pendingSessionIds, sessionId};
    _error = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      _error = redactSecrets(error);
      rethrow;
    } finally {
      _pendingSessionIds = {..._pendingSessionIds}..remove(sessionId);
      notifyListeners();
    }
  }

  Future<void> _connect(int generation) async {
    final session = _session;
    if (session == null || generation != _generation) return;
    try {
      final channel = WebSocketChannel.connect(_client.webSocketUri(session));
      await channel.ready.timeout(const Duration(seconds: 10));
      if (generation != _generation) {
        await channel.sink.close(socket_status.goingAway);
        return;
      }
      _channel = channel;
      _connected = true;
      _reconnectAttempt = 0;
      _error = null;
      _sendSocket('SessionsStart', '0,1500');
      _socketSubscription = channel.stream.listen(
        (message) => _onSocketMessage(message, generation),
        onError: (_) => _socketClosed(generation),
        onDone: () => _socketClosed(generation),
      );
      notifyListeners();
    } catch (error) {
      if (generation != _generation) return;
      _error = 'Live device updates are unavailable: ${redactSecrets(error)}';
      _socketClosed(generation);
    }
  }

  void _onSocketMessage(Object? raw, int generation) {
    if (generation != _generation || raw is! String) return;
    try {
      final message = jsonDecode(raw) as Map<String, dynamic>;
      final type = message['MessageType'] as String?;
      if (type == 'ForceKeepAlive') {
        final seconds = _intValue(message['Data']).clamp(10, 120);
        _keepAliveTimer?.cancel();
        _keepAliveTimer = Timer.periodic(
          Duration(seconds: math.max(5, seconds ~/ 2)),
          (_) => _sendSocket('KeepAlive'),
        );
        _sendSocket('KeepAlive');
        return;
      }
      if (type == 'Sessions') {
        final data = message['Data'];
        if (data is List<dynamic>) _acceptSessions(data);
        return;
      }
      final data = message['Data'];
      if (data is! Map<String, dynamic>) return;
      _commandQueue = _commandQueue
          .then((_) => _commands.handle(type, data))
          .catchError((Object error) {
            _error = 'A remote command failed: ${redactSecrets(error)}';
            notifyListeners();
          });
    } catch (_) {}
  }

  void _acceptSessions(List<dynamic> rows) {
    final session = _session;
    if (session == null) return;
    _sessions = rows
        .whereType<Map<String, dynamic>>()
        .map(RemoteSession.fromJson)
        .where(
          (item) =>
              item.userId == session.userId &&
              item.client == 'Spotifin' &&
              item.deviceId != session.deviceId &&
              item.supportsMediaControl &&
              item.isActive,
        )
        .toList(growable: false);
    notifyListeners();
  }

  void _sendSocket(String type, [Object? data]) {
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(jsonEncode({'MessageType': type, 'Data': ?data}));
  }

  void _socketClosed(int generation) {
    if (generation != _generation) return;
    if (_channel == null && _reconnectTimer?.isActive == true) return;
    _socketSubscription?.cancel();
    _socketSubscription = null;
    _channel = null;
    _connected = false;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    notifyListeners();
    _reconnectTimer?.cancel();
    final seconds = math.min(30, 1 << math.min(_reconnectAttempt++, 5));
    _reconnectTimer = Timer(
      Duration(seconds: seconds),
      () => unawaited(_reconnect(generation)),
    );
  }

  Future<void> _reconnect(int generation) async {
    final session = _session;
    if (session == null || generation != _generation) return;
    try {
      await _client.advertiseRemoteCapabilities(session);
    } catch (_) {}
    await _connect(generation);
  }

  Future<void> clear() async {
    _generation++;
    _pollTimer?.cancel();
    _pollTimer = null;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    if (_channel != null) _sendSocket('SessionsStop');
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    await _channel?.sink.close(socket_status.goingAway);
    _channel = null;
    _session = null;
    _sessions = const [];
    _pendingSessionIds = const {};
    _connected = false;
    _loading = false;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _generation++;
    _pollTimer?.cancel();
    _keepAliveTimer?.cancel();
    _reconnectTimer?.cancel();
    if (_channel != null) _sendSocket('SessionsStop');
    unawaited(_socketSubscription?.cancel());
    unawaited(_channel?.sink.close(socket_status.goingAway));
    _socketSubscription = null;
    _channel = null;
    _session = null;
    super.dispose();
  }
}

int _intValue(Object? value) => switch (value) {
  int number => number,
  num number => number.round(),
  String text => int.tryParse(text) ?? 0,
  _ => 0,
};
