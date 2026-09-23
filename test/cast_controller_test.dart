import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/services/cast/cast_controller.dart';
import 'package:spotifin/services/cast/cast_device.dart';
import 'package:spotifin/services/cast/cast_media.dart';
import 'package:spotifin/services/cast/cast_playback_source.dart';
import 'package:spotifin/services/cast/cast_sender.dart';
import 'package:spotifin/services/cast/jellyfin_cast_adapter.dart';
import 'package:spotifin/services/jellyfin/jellyfin_client.dart';
import 'package:spotifin/services/jellyfin/session.dart';
import 'package:spotifin/storage/database.dart';

Track track(String id, {String container = 'mp3'}) => Track(
  id: id,
  name: 'Song $id',
  album: 'Album',
  albumId: 'album-$id',
  artist: 'Artist',
  artistItems: '[]',
  labels: '[]',
  durationTicks: 1800000000,
  container: container,
  favorite: false,
  playCount: 0,
);

const httpsSession = JellyfinSession(
  serverUrl: 'https://music.example.com/jellyfin',
  serverId: 'server',
  deviceId: 'phone',
  userId: 'user',
  userName: 'Pablo',
  accessToken: 'token',
);

const httpSession = JellyfinSession(
  serverUrl: 'http://192.168.1.10:8096',
  serverId: 'server',
  deviceId: 'phone',
  userId: 'user',
  userName: 'Pablo',
  accessToken: 'token',
);

class FakeSender implements CastSender {
  FakeSender({List<CastDevice>? devices})
    : _devices = List.of(devices ?? const []);

  List<CastDevice> _devices;
  final devicesController = StreamController<List<CastDevice>>.broadcast();
  final connectionController =
      StreamController<CastConnectionState>.broadcast();
  final remoteController = StreamController<CastRemoteState>.broadcast();

  CastConnectionState _connection = CastConnectionState.disconnected;
  CastDevice? _connectedDevice;
  CastRemoteState _remote = const CastRemoteState();
  String? initializedAppId;
  int failLoadCount = 0;
  final loads = <CastTrackPayload>[];
  final loadPositions = <Duration>[];
  final calls = <String>[];

  void emitDevices(List<CastDevice> devices) {
    _devices = List.of(devices);
    devicesController.add(devicesStreamValue);
  }

  List<CastDevice> get devicesStreamValue => List.unmodifiable(_devices);

  void emitConnection(CastConnectionState state, [CastDevice? device]) {
    _connection = state;
    if (device != null) _connectedDevice = device;
    if (state == CastConnectionState.disconnected) _connectedDevice = null;
    connectionController.add(state);
  }

  void emitRemote(CastRemoteState state) {
    _remote = state;
    remoteController.add(state);
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
  Future<void> initialize({required String receiverAppId}) async {
    initializedAppId = receiverAppId;
  }

  @override
  Future<void> startDiscovery() async {}

  @override
  Future<void> stopDiscovery() async {}

  @override
  Future<void> connect(CastDevice device) async {
    calls.add('connect:${device.id}');
    _connectedDevice = device;
    _connection = CastConnectionState.connected;
    connectionController.add(_connection);
  }

  @override
  Future<void> disconnect({bool stopReceiver = false}) async {
    calls.add('disconnect');
    _connectedDevice = null;
    _connection = CastConnectionState.disconnected;
    _remote = const CastRemoteState();
    connectionController.add(_connection);
    remoteController.add(_remote);
  }

  @override
  Future<void> loadSingle(
    CastTrackPayload payload, {
    required Duration position,
    bool autoplay = true,
  }) async {
    loads.add(payload);
    loadPositions.add(position);
    if (failLoadCount > 0) {
      failLoadCount--;
      throw const CastException('Receiver rejected this track.');
    }
    _remote = _remote.copyWith(
      position: position,
      duration: payload.duration,
      playerState: autoplay ? CastPlayerState.playing : CastPlayerState.paused,
    );
    remoteController.add(_remote);
  }

  @override
  Future<void> play() async {
    calls.add('play');
    _remote = _remote.copyWith(playerState: CastPlayerState.playing);
    remoteController.add(_remote);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    _remote = _remote.copyWith(playerState: CastPlayerState.paused);
    remoteController.add(_remote);
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    _remote = _remote.copyWith(playerState: CastPlayerState.idle);
    remoteController.add(_remote);
  }

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek:${position.inSeconds}');
    _remote = _remote.copyWith(position: position);
    remoteController.add(_remote);
  }

  @override
  Future<void> setVolume(double volume) async {
    calls.add('volume:$volume');
    _remote = _remote.copyWith(volume: volume.clamp(0.0, 1.0));
    remoteController.add(_remote);
  }

  @override
  Future<void> next() async {
    calls.add('next');
  }

  @override
  Future<void> previous() async {
    calls.add('previous');
  }

  @override
  void dispose() {
    devicesController.close();
    connectionController.close();
    remoteController.close();
  }
}

class FakePlayback implements CastPlaybackSource {
  FakePlayback({required List<Track> queue, int index = 0})
    : _queue = List.of(queue),
      // ignore: prefer_initializing_formals
      _index = index;

  final List<Track> _queue;
  int _index;
  Duration _position = const Duration(seconds: 12);
  bool castingActive = false;
  int stopForCastCalls = 0;
  final playIndexCalls = <int>[];
  final seekCalls = <Duration>[];
  int playCalls = 0;
  int pauseCalls = 0;

  @override
  Track? get currentTrack =>
      _queue.isEmpty ? null : _queue[_index.clamp(0, _queue.length - 1)];

  @override
  List<Track> get queue => List.unmodifiable(_queue);

  @override
  int? get currentIndex => _queue.isEmpty ? null : _index;

  @override
  Duration get position => _position;

  set position(Duration value) => _position = value;

  @override
  Future<void> stopForCast() async {
    stopForCastCalls++;
  }

  @override
  Future<void> playQueueIndex(int index) async {
    playIndexCalls.add(index);
    _index = index.clamp(0, _queue.length - 1);
  }

  @override
  Future<void> seek(Duration position) async {
    seekCalls.add(position);
    _position = position;
  }

  @override
  Future<void> play() async {
    playCalls++;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  void setCastingActive(bool active) {
    castingActive = active;
  }
}

CastController controller({
  required FakePlayback playback,
  required FakeSender sender,
  JellyfinSession? session = httpsSession,
  bool supported = true,
}) {
  final instance = CastController(
    playback: playback,
    adapter: JellyfinCastAdapter(JellyfinClient()),
    sender: sender,
    isSupported: () => supported,
  );
  instance.configure(session);
  return instance;
}

const livingRoom = CastDevice(id: 'room', friendlyName: 'Living Room');

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  test('discovers, connects, and hands off with queue preserved', () async {
    final playback = FakePlayback(
      queue: [track('a'), track('b'), track('c')],
      index: 1,
    );
    final sender = FakeSender(devices: [livingRoom]);
    final cast = controller(playback: playback, sender: sender);
    addTearDown(sender.dispose);
    addTearDown(cast.dispose);

    await cast.initialize();
    await pump();
    expect(cast.devices.map((d) => d.id), ['room']);

    await cast.connect(livingRoom);
    await pump();

    expect(sender.initializedAppId, 'F007D354');
    expect(cast.connectionState, CastConnectionState.connected);
    expect(cast.isCasting, isTrue);
    expect(cast.remoteTrack?.id, 'b');
    expect(cast.remoteIndex, 1);
    // Local queue/history untouched: same objects, same order.
    expect(playback.queue.map((t) => t.id), ['a', 'b', 'c']);
    expect(playback.currentIndex, 1);
    expect(playback.stopForCastCalls, 1);
    expect(playback.castingActive, isTrue);
    // Handoff payload carries metadata + position, ids only in customData.
    final payload = sender.loads.single;
    expect(payload.title, 'Song b');
    expect(payload.artist, 'Artist');
    expect(sender.loadPositions.single, const Duration(seconds: 12));
    expect(payload.customData, {'itemId': 'b'});
    expect(payload.contentUrl.toString(), isNot(contains('password')));
  });

  test('transport controls drive the receiver', () async {
    final playback = FakePlayback(
      queue: [track('a'), track('b'), track('c')],
      index: 0,
    );
    final sender = FakeSender(devices: [livingRoom]);
    final cast = controller(playback: playback, sender: sender);
    addTearDown(sender.dispose);
    addTearDown(cast.dispose);

    await cast.initialize();
    await cast.connect(livingRoom);
    await pump();

    await cast.toggle();
    expect(sender.calls, contains('pause'));
    await cast.toggle();
    expect(sender.calls, contains('play'));

    await cast.seek(const Duration(seconds: 30));
    expect(sender.calls, contains('seek:30'));

    await cast.setVolume(2.5);
    expect(sender.calls.last, 'volume:1.0');

    await cast.next();
    await pump();
    expect(cast.remoteTrack?.id, 'b');
    expect(sender.loads.length, 2);

    // Well into the track: previous restarts instead of changing index.
    sender.emitRemote(
      const CastRemoteState(
        playerState: CastPlayerState.playing,
        position: Duration(seconds: 30),
        duration: Duration(minutes: 3),
      ),
    );
    await pump();
    await cast.previous();
    expect(sender.calls, contains('seek:0'));
    expect(cast.remoteTrack?.id, 'b');
  });

  test('next at the end of the queue is an explicit error', () async {
    final playback = FakePlayback(queue: [track('a')], index: 0);
    final sender = FakeSender(devices: [livingRoom]);
    final cast = controller(playback: playback, sender: sender);
    addTearDown(sender.dispose);
    addTearDown(cast.dispose);

    await cast.initialize();
    await cast.connect(livingRoom);
    await pump();

    await expectLater(cast.next(), throwsA(isA<CastException>()));
    expect(cast.error, contains('end of the queue'));
  });

  test('failed handoff retries once with the AAC fallback', () async {
    final playback = FakePlayback(
      queue: [track('a', container: 'flac')],
      index: 0,
    );
    final sender = FakeSender(devices: [livingRoom])..failLoadCount = 1;
    final cast = controller(playback: playback, sender: sender);
    addTearDown(sender.dispose);
    addTearDown(cast.dispose);

    await cast.initialize();
    await cast.connect(livingRoom);
    await pump();

    expect(cast.isCasting, isTrue);
    expect(sender.loads.length, 2);
    expect(sender.loads.last.contentType, 'audio/mp4');
  });

  test('persistent handoff failure surfaces and un-suppresses local', () async {
    final playback = FakePlayback(queue: [track('a')], index: 0);
    final sender = FakeSender(devices: [livingRoom])..failLoadCount = 10;
    final cast = controller(playback: playback, sender: sender);
    addTearDown(sender.dispose);
    addTearDown(cast.dispose);

    await cast.initialize();
    await expectLater(cast.connect(livingRoom), throwsA(isA<CastException>()));
    expect(cast.isCasting, isFalse);
    expect(cast.error, isNotNull);
    expect(playback.castingActive, isFalse);
  });

  test('connection loss offers retry and disconnect resumes locally', () async {
    final playback = FakePlayback(
      queue: [track('a'), track('b'), track('c')],
      index: 0,
    );
    final sender = FakeSender(devices: [livingRoom]);
    final cast = controller(playback: playback, sender: sender);
    addTearDown(sender.dispose);
    addTearDown(cast.dispose);

    await cast.initialize();
    await cast.connect(livingRoom);
    await pump();
    await cast.next();
    await pump();
    sender.emitRemote(
      const CastRemoteState(
        playerState: CastPlayerState.playing,
        position: Duration(seconds: 25),
        duration: Duration(minutes: 3),
      ),
    );
    await pump();

    // Receiver disappears mid-cast.
    sender.emitConnection(CastConnectionState.disconnected);
    await pump();
    expect(cast.error, contains('connection lost'));

    // Retry rejoins and reloads at the last known position.
    await cast.retry();
    await pump();
    expect(sender.calls, contains('connect:room'));
    expect(sender.loadPositions.last, const Duration(seconds: 25));

    // Disconnect resumes the untouched local queue where remote left off.
    await cast.disconnect();
    await pump();
    expect(cast.isCasting, isFalse);
    expect(playback.castingActive, isFalse);
    expect(playback.playIndexCalls, [1]);
    expect(playback.seekCalls.last, const Duration(seconds: 25));
    expect(playback.playCalls, greaterThanOrEqualTo(1));
    expect(playback.queue.map((t) => t.id), ['a', 'b', 'c']);
  });

  test('unavailable reasons are explicit', () async {
    final noSession = controller(
      playback: FakePlayback(queue: [track('a')], index: 0),
      sender: FakeSender(devices: [livingRoom]),
      session: null,
    );
    addTearDown(noSession.dispose);
    expect(noSession.unavailableReason, contains('Sign in'));
    expect(noSession.canCast, isFalse);

    final http = controller(
      playback: FakePlayback(queue: [track('a')], index: 0),
      sender: FakeSender(devices: [livingRoom]),
      session: httpSession,
    );
    addTearDown(http.dispose);
    expect(http.unavailableReason, contains('plain HTTP'));

    final empty = controller(
      playback: FakePlayback(queue: const [], index: 0),
      sender: FakeSender(devices: [livingRoom]),
    );
    addTearDown(empty.dispose);
    expect(empty.unavailableReason, contains('Nothing playing'));

    final unsupported = controller(
      playback: FakePlayback(queue: [track('a')], index: 0),
      sender: FakeSender(devices: [livingRoom]),
      supported: false,
    );
    addTearDown(unsupported.dispose);
    expect(unsupported.unavailableReason, contains('iPhone and Android'));
    await expectLater(unsupported.castCurrent(), throwsA(isA<CastException>()));
  });

  test('target disappearance while connected is surfaced', () async {
    final playback = FakePlayback(queue: [track('a')], index: 0);
    final sender = FakeSender(devices: [livingRoom]);
    final cast = controller(playback: playback, sender: sender);
    addTearDown(sender.dispose);
    addTearDown(cast.dispose);

    await cast.initialize();
    await cast.connect(livingRoom);
    await pump();
    sender.emitDevices(const [
      CastDevice(id: 'other', friendlyName: 'Other Room'),
    ]);
    await pump();
    expect(cast.error, contains('no longer available'));
  });
}
