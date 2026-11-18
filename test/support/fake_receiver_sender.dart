import 'dart:async';
import 'dart:convert';

import 'package:spotifin/services/cast/cast_device.dart';
import 'package:spotifin/services/cast/cast_sender.dart';

/// [CastSender] that behaves like the Jellyfin Cast receiver: it keeps the
/// playlist sent with `PlayNow`/`PlayLast`, advances on its own when a track
/// finishes, and reports the playing item id in its media status.
class FakeReceiverSender implements CastSender {
  FakeReceiverSender({List<CastDevice> devices = const []})
    : _devices = List.of(devices);

  final devicesController = StreamController<List<CastDevice>>.broadcast();
  final connectionController =
      StreamController<CastConnectionState>.broadcast();
  final remoteController = StreamController<CastRemoteState>.broadcast();
  final receiverMessagesController = StreamController<String>.broadcast();

  List<CastDevice> _devices;
  CastConnectionState _connection = CastConnectionState.disconnected;
  CastDevice? _connectedDevice;
  CastRemoteState _remote = const CastRemoteState();

  /// Receiver-side playlist and position in it.
  List<String> playlist = [];
  int index = -1;
  String repeatMode = 'RepeatNone';

  /// Every command sent on the receiver namespace, decoded.
  final commands = <Map<String, Object?>>[];
  final calls = <String>[];

  int failCommandCount = 0;
  int failConnectCount = 0;
  bool failDisconnect = false;
  bool connectStaysConnecting = false;
  Completer<void>? connectGate;
  Completer<void>? commandGate;
  bool? stoppedReceiver;
  int stopCalls = 0;
  int disposeCalls = 0;
  int initializeCalls = 0;
  int startDiscoveryCalls = 0;
  String? initializedAppId;

  List<String> get commandNames => [
    for (final command in commands) command['command']! as String,
  ];

  Map<String, Object?> lastCommand(String name) =>
      commands.lastWhere((command) => command['command'] == name);

  Map<String, Object?> lastOptions(String name) =>
      lastCommand(name)['options']! as Map<String, Object?>;

  List<String> itemIdsOf(Map<String, Object?> options) => [
    for (final item in options['items']! as List) (item as Map)['Id'] as String,
  ];

  String? get playingItemId =>
      index >= 0 && index < playlist.length ? playlist[index] : null;

  void emitConnection(CastConnectionState state, [CastDevice? device]) {
    _connection = state;
    if (device != null) _connectedDevice = device;
    if (state == CastConnectionState.disconnected) {
      _connectedDevice = null;
      _remote = CastRemoteState(volume: _remote.volume);
      remoteController.add(_remote);
    }
    connectionController.add(state);
  }

  void emitRemote(CastRemoteState state) {
    _remote = state;
    remoteController.add(state);
  }

  void emitReceiverMessage(Map<String, Object?> message) =>
      receiverMessagesController.add(jsonEncode(message));

  /// Reports the current item playing (or paused) at [position].
  void reportPlaying({
    Duration position = Duration.zero,
    CastPlayerState state = CastPlayerState.playing,
  }) => emitRemote(
    CastRemoteState(
      playerState: state,
      position: position,
      duration: const Duration(minutes: 3),
      volume: _remote.volume,
      itemId: playingItemId,
    ),
  );

  /// The current track ends: the receiver reports it finished, then plays
  /// its next item on its own (or goes idle at the end of its playlist).
  void finishCurrent() {
    emitRemote(
      CastRemoteState(
        playerState: CastPlayerState.idle,
        position: const Duration(minutes: 3),
        duration: const Duration(minutes: 3),
        volume: _remote.volume,
        finishReason: CastFinishReason.finished,
        itemId: playingItemId,
      ),
    );
    if (repeatMode == 'RepeatOne') {
      reportPlaying();
      return;
    }
    if (index + 1 < playlist.length) {
      index++;
      reportPlaying();
    } else if (repeatMode == 'RepeatAll' && playlist.isNotEmpty) {
      index = 0;
      reportPlaying();
    }
  }

  @override
  List<CastDevice> get devices => List.unmodifiable(_devices);

  @override
  Stream<List<CastDevice>> get devicesStream => devicesController.stream;

  @override
  CastConnectionState get connectionState => _connection;

  @override
  Stream<CastConnectionState> get connectionStateStream =>
      connectionController.stream;

  @override
  CastDevice? get connectedDevice => _connectedDevice;

  @override
  CastRemoteState get remoteState => _remote;

  @override
  Stream<CastRemoteState> get remoteStateStream => remoteController.stream;

  @override
  Stream<String> get receiverMessages => receiverMessagesController.stream;

  @override
  Future<void> initialize({required String receiverAppId}) async {
    initializeCalls++;
    initializedAppId = receiverAppId;
  }

  @override
  Future<void> startDiscovery() async {
    startDiscoveryCalls++;
  }

  @override
  Future<void> stopDiscovery() async {}

  @override
  Future<void> connect(CastDevice device) async {
    calls.add('connect:${device.id}');
    final gate = connectGate;
    if (gate != null) await gate.future;
    if (failConnectCount > 0) {
      failConnectCount--;
      throw const CastException('Could not connect to this Chromecast.');
    }
    _connectedDevice = device;
    _connection = connectStaysConnecting
        ? CastConnectionState.connecting
        : CastConnectionState.connected;
    connectionController.add(_connection);
  }

  @override
  Future<void> disconnect({bool stopReceiver = false}) async {
    calls.add('disconnect');
    stoppedReceiver = stopReceiver;
    if (failDisconnect) throw const CastException('Could not stop receiver.');
    playlist = [];
    index = -1;
    emitConnection(CastConnectionState.disconnected);
  }

  @override
  Future<void> sendReceiverCommand(Map<String, Object?> command) async {
    commands.add(jsonDecode(jsonEncode(command)) as Map<String, Object?>);
    final gate = commandGate;
    if (gate != null) await gate.future;
    if (failCommandCount > 0) {
      failCommandCount--;
      throw const CastException('Chromecast did not accept the command.');
    }
    final options = command['options']! as Map<String, Object?>;
    switch (command['command']) {
      case 'PlayNow':
        playlist = itemIdsOf(options);
        index = options['startIndex']! as int;
        final ticks = options['startPositionTicks'] as int? ?? 0;
        reportPlaying(position: Duration(microseconds: ticks ~/ 10));
      case 'PlayLast':
        playlist = [...playlist, ...itemIdsOf(options)];
      case 'NextTrack':
        if (index + 1 < playlist.length) {
          index++;
          reportPlaying();
        }
      case 'PreviousTrack':
        if (index > 0) {
          index--;
          reportPlaying();
        }
      case 'Seek':
        final seconds = options['position']! as num;
        emitRemote(
          _remote.copyWith(
            position: Duration(milliseconds: (seconds * 1000).round()),
          ),
        );
      case 'SetRepeatMode':
        repeatMode = options['RepeatMode']! as String;
    }
  }

  @override
  Future<void> play() async {
    calls.add('play');
    emitRemote(_remote.copyWith(playerState: CastPlayerState.playing));
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    emitRemote(_remote.copyWith(playerState: CastPlayerState.paused));
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    stopCalls++;
    emitRemote(_remote.copyWith(playerState: CastPlayerState.idle));
  }

  @override
  Future<void> setVolume(double volume) async {
    calls.add('volume:$volume');
    emitRemote(_remote.copyWith(volume: volume.clamp(0.0, 1.0)));
  }

  void setDevices(List<CastDevice> devices) {
    _devices = List.of(devices);
    devicesController.add(this.devices);
  }

  @override
  void dispose() {
    disposeCalls++;
    devicesController.close();
    connectionController.close();
    remoteController.close();
    receiverMessagesController.close();
  }
}
