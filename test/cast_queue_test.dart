import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:spotifin/services/cast/cast_controller.dart';
import 'package:spotifin/services/cast/cast_device.dart';
import 'package:spotifin/services/cast/cast_media.dart';
import 'package:spotifin/services/cast/cast_playback_source.dart';
import 'package:spotifin/services/cast/cast_sender.dart';
import 'package:spotifin/services/cast/jellyfin_cast_adapter.dart';
import 'package:spotifin/services/jellyfin/jellyfin_client.dart';
import 'package:spotifin/services/jellyfin/session.dart';
import 'package:spotifin/services/playback/playback_snapshot.dart';
import 'package:spotifin/services/playback/queue_state.dart';
import 'package:spotifin/storage/database.dart';

const _session = JellyfinSession(
  serverUrl: 'https://music.example.com/jellyfin',
  serverId: 'server',
  deviceId: 'phone',
  userId: 'user',
  userName: 'Pablo',
  accessToken: 'token',
);

const _device = CastDevice(id: 'room', friendlyName: 'Living Room');

Track _track(String id) => Track(
  id: id,
  name: 'Song $id',
  album: 'Album',
  albumId: 'album-$id',
  artist: 'Artist',
  artistItems: '[]',
  labels: '[]',
  durationTicks: 1800000000,
  container: 'mp3',
  favorite: false,
  playCount: 0,
);

Future<void> _pump() => Future<void>.delayed(Duration.zero);

class _QueueSender implements CastSender {
  final connectionController =
      StreamController<CastConnectionState>.broadcast();
  final remoteController = StreamController<CastRemoteState>.broadcast();

  CastConnectionState _connection = CastConnectionState.disconnected;
  CastDevice? _connectedDevice;
  CastRemoteState _remote = const CastRemoteState();

  int failLoadCount = 0;
  final loads = <CastTrackPayload>[];
  final loadAutoplays = <bool>[];
  int stopCalls = 0;
  int localPlayCount = 0;

  void emitConnection(CastConnectionState state) {
    _connection = state;
    if (state == CastConnectionState.disconnected) _connectedDevice = null;
    connectionController.add(state);
  }

  void emitRemote(CastRemoteState state) {
    _remote = state;
    remoteController.add(state);
  }

  @override
  List<CastDevice> get devices => const [_device];

  @override
  Stream<List<CastDevice>> get devicesStream => Stream.value(devices);

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
  Future<void> initialize({required String receiverAppId}) async {}

  @override
  Future<void> startDiscovery() async {}

  @override
  Future<void> stopDiscovery() async {}

  @override
  Future<void> connect(CastDevice device) async {
    _connectedDevice = device;
    _connection = CastConnectionState.connected;
    connectionController.add(_connection);
  }

  @override
  Future<void> disconnect({bool stopReceiver = false}) async {
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
    loadAutoplays.add(autoplay);
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
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {
    stopCalls++;
    _remote = _remote.copyWith(playerState: CastPlayerState.idle);
    remoteController.add(_remote);
  }

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> next() async {}

  @override
  Future<void> previous() async {}

  @override
  void dispose() {
    connectionController.close();
    remoteController.close();
  }
}

class _QueuePlayback implements CastPlaybackSource {
  _QueuePlayback(this.snapshotQueue);

  QueueState snapshotQueue;
  bool castingActive = false;
  int stopForCastCalls = 0;
  int localPlayCalls = 0;
  final restoredSnapshots = <PlaybackSnapshot>[];

  @override
  Track? get currentTrack => snapshotQueue.currentEntry?.track;

  @override
  List<Track> get queue => snapshotQueue.loadedTracks;

  @override
  int? get currentIndex => snapshotQueue.currentIndex;

  @override
  Duration get position => const Duration(seconds: 12);

  @override
  bool get playing => true;

  @override
  Future<void> stopForCast() async {
    stopForCastCalls++;
  }

  @override
  Future<void> playQueueIndex(int index) async {
    localPlayCalls++;
  }

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> play() async {
    localPlayCalls++;
  }

  @override
  Future<void> pause() async {}

  @override
  void setCastingActive(bool active) {
    castingActive = active;
  }

  @override
  PlaybackSnapshot captureSnapshot() => PlaybackSnapshot(
    queue: snapshotQueue,
    position: position,
    playing: true,
    repeatMode: LoopMode.off,
    history: const [],
  );

  @override
  Future<void> restoreSnapshot(PlaybackSnapshot snapshot) async {
    restoredSnapshots.add(snapshot);
  }

  @override
  Future<void> reportCurrentState() async {}
}

int _ids = 0;
String _newId() => 'queue-${_ids++}';

QueueState _prepared(List<String> ids, {int start = 0}) => QueueState.prepare(
  [for (final id in ids) _track(id)],
  startIndex: start,
  shuffle: false,
  newId: _newId,
);

Future<CastController> _connected(
  _QueuePlayback playback,
  _QueueSender sender,
) async {
  final cast = CastController(
    playback: playback,
    adapter: JellyfinCastAdapter(JellyfinClient()),
    sender: sender,
    isSupported: () => true,
    random: Random(7),
  );
  addTearDown(sender.dispose);
  addTearDown(cast.dispose);
  await cast.configure(_session);
  await cast.connect(_device);
  await _pump();
  expect(cast.ownership, CastOwnership.remote);
  return cast;
}

void main() {
  test('new collection loads the chosen entry and commits', () async {
    final playback = _QueuePlayback(_prepared(['a', 'b', 'c'], start: 0));
    final sender = _QueueSender();
    final cast = await _connected(playback, sender);
    final handoffLoads = sender.loads.length;
    expect(handoffLoads, 1);

    await cast.replaceQueue([
      _track('x'),
      _track('y'),
      _track('z'),
    ], startIndex: 2);
    await _pump();

    expect(sender.loads.length, handoffLoads + 1);
    expect(sender.loads.last.itemId, 'z');
    expect(cast.castQueue.map((track) => track.id), ['x', 'y', 'z']);
    expect(cast.remoteTrack?.id, 'z');
    expect(cast.remoteIndex, 2);
    // Local audio never started: only the handoff stop ran.
    expect(playback.stopForCastCalls, 1);
    expect(playback.localPlayCalls, 0);
  });

  test('pure edits commit without a receiver load', () async {
    final playback = _QueuePlayback(_prepared(['a', 'b', 'c', 'd'], start: 1));
    final sender = _QueueSender();
    final cast = await _connected(playback, sender);
    final loads = sender.loads.length;

    await cast.addToQueue(_track('e'));
    await cast.addNextToQueue([_track('f')]);
    await cast.reorder(3, 1);
    await cast.removeAt(0);
    await _pump();

    expect(sender.loads.length, loads);
    expect(cast.remoteTrack?.id, 'b');
    expect(cast.castQueue.map((track) => track.id), ['c', 'b', 'f', 'd', 'e']);
    expect(playback.localPlayCalls, 0);
  });

  test('removing the current entry loads its successor paused-aware', () async {
    final playback = _QueuePlayback(_prepared(['a', 'b', 'c'], start: 1));
    final sender = _QueueSender();
    final cast = await _connected(playback, sender);
    sender.emitRemote(
      const CastRemoteState(
        playerState: CastPlayerState.paused,
        position: Duration(seconds: 9),
        duration: Duration(minutes: 3),
      ),
    );
    await _pump();

    await cast.removeAt(1);
    await _pump();

    expect(sender.loads.length, 2);
    expect(sender.loads.last.itemId, 'c');
    expect(sender.loadAutoplays.last, isFalse);
    expect(cast.castQueue.map((track) => track.id), ['a', 'c']);
    expect(cast.remoteTrack?.id, 'c');
    expect(playback.localPlayCalls, 0);
  });

  test(
    'removing the final entry stops the receiver and keeps casting',
    () async {
      final playback = _QueuePlayback(_prepared(['a'], start: 0));
      final sender = _QueueSender();
      final cast = await _connected(playback, sender);

      await cast.removeAt(0);
      await _pump();

      expect(sender.stopCalls, 1);
      expect(cast.castQueue, isEmpty);
      expect(cast.ownership, CastOwnership.remote);
      expect(sender.connectionState, CastConnectionState.connected);

      // A new selection on the empty queue loads and commits.
      await cast.replaceQueue([_track('n')], startIndex: 0);
      await _pump();
      expect(cast.castQueue.map((track) => track.id), ['n']);
      expect(cast.remoteTrack?.id, 'n');
    },
  );

  test('history selection inserts next and updates history', () async {
    final playback = _QueuePlayback(_prepared(['a', 'b', 'c'], start: 0));
    final sender = _QueueSender();
    final cast = await _connected(playback, sender);

    await cast.playHistoryTrack(_track('h'));
    await _pump();

    expect(sender.loads.length, 2);
    expect(sender.loads.last.itemId, 'h');
    expect(cast.castQueue.map((track) => track.id), ['a', 'h', 'b', 'c']);
    expect(cast.remoteTrack?.id, 'h');
    expect(playback.localPlayCalls, 0);
  });

  test('shuffle preserves current without restarting audio', () async {
    final playback = _QueuePlayback(
      _prepared(['a', 'b', 'c', 'd', 'e'], start: 1),
    );
    final sender = _QueueSender();
    final cast = await _connected(playback, sender);
    final loads = sender.loads.length;

    await cast.toggleShuffle();
    await _pump();

    expect(sender.loads.length, loads);
    expect(cast.remoteTrack?.id, 'b');
    expect(cast.castQueue.map((track) => track.id).toSet(), {
      'a',
      'b',
      'c',
      'd',
      'e',
    });
    // Loaded prefix through current is untouched.
    expect(cast.castQueue.first.id, 'a');
  });

  test('commands are rejected while not remote', () async {
    final playback = _QueuePlayback(_prepared(['a', 'b'], start: 0));
    final sender = _QueueSender();
    final cast = CastController(
      playback: playback,
      adapter: JellyfinCastAdapter(JellyfinClient()),
      sender: sender,
      isSupported: () => true,
    );
    addTearDown(sender.dispose);
    addTearDown(cast.dispose);
    await cast.configure(_session);

    // Local ownership: ordinary commands fail and change nothing.
    await expectLater(
      cast.addToQueue(_track('x')),
      throwsA(isA<CastException>()),
    );
    expect(sender.loads, isEmpty);

    await cast.connect(_device);
    await _pump();
    sender.emitConnection(CastConnectionState.disconnected);
    await _pump();
    expect(cast.ownership, CastOwnership.recovering);

    await expectLater(cast.removeAt(0), throwsA(isA<CastException>()));
    expect(cast.castQueue.map((track) => track.id), ['a', 'b']);
    expect(playback.localPlayCalls, 0);
  });

  test('failed selection retains prior state and restores the item', () async {
    final playback = _QueuePlayback(_prepared(['a', 'b', 'c'], start: 0));
    final sender = _QueueSender();
    final cast = await _connected(playback, sender);
    // Fail both the initial and AAC-fallback selection loads; the prior
    // item restore below succeeds.
    sender.failLoadCount = 2;

    await expectLater(cast.playIndex(2), throwsA(isA<CastException>()));
    await _pump();

    // Prior snapshot retained; the prior item was reloaded in place.
    expect(cast.remoteTrack?.id, 'a');
    expect(cast.ownership, CastOwnership.remote);
    expect(cast.error, isNotNull);
    expect(playback.localPlayCalls, 0);

    // Retry of the same selection succeeds.
    await cast.playIndex(2);
    await _pump();
    expect(cast.remoteTrack?.id, 'c');
  });

  test('failed selection with failed restore keeps recovery', () async {
    final playback = _QueuePlayback(_prepared(['a', 'b'], start: 0));
    final sender = _QueueSender();
    final cast = await _connected(playback, sender);
    // Fail selection and the prior-item restore (initial + fallback each).
    sender.failLoadCount = 10;

    await expectLater(cast.playIndex(1), throwsA(isA<CastException>()));
    await _pump();

    expect(cast.ownership, CastOwnership.recovering);
    expect(cast.remoteTrack?.id, 'a');
    expect(playback.localPlayCalls, 0);
  });

  test('duplicate tracks keep distinct occurrence and payload ids', () async {
    final playback = _QueuePlayback(_prepared(['a', 'b', 'a'], start: 0));
    final sender = _QueueSender();
    final cast = await _connected(playback, sender);

    await cast.playIndex(2);
    await _pump();

    final handoffId = sender.loads.first.playlistItemId;
    final selectionId = sender.loads.last.playlistItemId;
    expect(handoffId, isNotNull);
    expect(selectionId, isNotNull);
    expect(selectionId, isNot(handoffId));
    expect(sender.loads.last.itemId, 'a');
    expect(cast.remoteIndex, 2);

    await cast.removeTrack('a');
    await _pump();
    expect(cast.castQueue.map((track) => track.id), ['b']);
  });

  test('edits survive disconnect into the resumed snapshot', () async {
    final playback = _QueuePlayback(_prepared(['a', 'b'], start: 0));
    final sender = _QueueSender();
    final cast = await _connected(playback, sender);

    await cast.addToQueue(_track('c'));
    await _pump();
    sender.emitConnection(CastConnectionState.disconnected);
    await _pump();
    await cast.disconnect();
    await _pump();

    expect(playback.restoredSnapshots, hasLength(1));
    final restored = playback.restoredSnapshots.single;
    expect(restored.queue.loadedEntries.map((entry) => entry.track.id), [
      'a',
      'b',
      'c',
    ]);
    expect(
      restored.queue.loadedEntries.map((entry) => entry.id).toSet(),
      hasLength(3),
    );
  });

  test('handoff beyond the window extends near the tail', () async {
    _ids = 1000;
    final local = QueueState.prepare(
      [for (var i = 0; i < 250; i++) _track('t-$i')],
      startIndex: 120,
      shuffle: false,
      newId: _newId,
    );
    final playback = _QueuePlayback(local);
    final sender = _QueueSender();
    final cast = await _connected(playback, sender);

    expect(cast.castQueue, hasLength(100));
    expect(cast.remoteTrack?.id, 't-120');

    await cast.playIndex(85);
    await cast.next();
    await _pump();

    expect(cast.castQueue.length, greaterThan(100));
    expect(cast.remoteTrack?.id, 't-186');
    expect(playback.localPlayCalls, 0);
  });
}
