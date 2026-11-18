import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:spotifin/services/cast/cast_controller.dart';
import 'package:spotifin/services/cast/cast_device.dart';
import 'package:spotifin/services/cast/cast_playback_source.dart';
import 'package:spotifin/services/cast/cast_sender.dart';
import 'package:spotifin/services/jellyfin/session.dart';
import 'package:spotifin/services/playback/playback_snapshot.dart';
import 'package:spotifin/services/playback/queue_state.dart';
import 'package:spotifin/storage/database.dart';

import 'support/fake_receiver_sender.dart';

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

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 30));

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

CastController _controller(_QueuePlayback playback, FakeReceiverSender sender) {
  final cast = CastController(
    playback: playback,
    sender: sender,
    isSupported: () => true,
    random: Random(7),
    resyncDelay: const Duration(milliseconds: 5),
  );
  addTearDown(sender.dispose);
  addTearDown(cast.dispose);
  return cast;
}

Future<CastController> _connected(
  _QueuePlayback playback,
  FakeReceiverSender sender,
) async {
  final cast = _controller(playback, sender);
  await cast.configure(_session);
  await cast.connect(_device);
  await _pump();
  expect(cast.ownership, CastOwnership.remote);
  return cast;
}

FakeReceiverSender _sender() => FakeReceiverSender(devices: const [_device]);

int _playNows(FakeReceiverSender sender) =>
    sender.commandNames.where((name) => name == 'PlayNow').length;

/// What the receiver will play from now on.
List<String> _receiverUpcoming(FakeReceiverSender sender) =>
    sender.playlist.sublist(sender.index);

List<String> _upcoming(CastController cast) =>
    cast.castQueue.skip(cast.remoteIndex).map((track) => track.id).toList();

void main() {
  test('new collection plays the chosen entry on the receiver', () async {
    final playback = _QueuePlayback(_prepared(['a', 'b', 'c'], start: 0));
    final sender = _sender();
    final cast = await _connected(playback, sender);

    await cast.replaceQueue([
      _track('x'),
      _track('y'),
      _track('z'),
    ], startIndex: 2);
    await _pump();

    final options = sender.lastOptions('PlayNow');
    expect(sender.itemIdsOf(options), ['x', 'y', 'z']);
    expect(options['startIndex'], 2);
    expect(cast.castQueue.map((track) => track.id), ['x', 'y', 'z']);
    expect(cast.remoteTrack?.id, 'z');
    expect(playback.stopForCastCalls, 1);
    expect(playback.localPlayCalls, 0);
  });

  test('appending reaches the receiver without interrupting it', () async {
    final playback = _QueuePlayback(_prepared(['a', 'b'], start: 0));
    final sender = _sender();
    final cast = await _connected(playback, sender);

    await cast.addToQueue(_track('c'));
    await _settle();

    expect(_playNows(sender), 1);
    expect(sender.commandNames.last, 'PlayLast');
    expect(sender.playlist, ['a', 'b', 'c']);
    expect(_receiverUpcoming(sender), _upcoming(cast));
  });

  test('reordering edits reach the receiver as one reload in place', () async {
    final playback = _QueuePlayback(_prepared(['a', 'b', 'c', 'd'], start: 1));
    final sender = _sender();
    final cast = await _connected(playback, sender);
    sender.reportPlaying(position: const Duration(seconds: 40));
    await _pump();

    await cast.addNextToQueue([_track('f')]);
    await cast.reorder(3, 1);
    await cast.removeAt(0);
    await _settle();

    expect(cast.remoteTrack?.id, 'b');
    expect(cast.castQueue.map((track) => track.id), ['c', 'b', 'f', 'd']);
    expect(_playNows(sender), 2);
    expect(sender.lastOptions('PlayNow')['startPositionTicks'], 400000000);
    expect(_receiverUpcoming(sender), _upcoming(cast));
    expect(playback.localPlayCalls, 0);
  });

  test('a reorder while paused waits for play to reach the receiver', () async {
    final playback = _QueuePlayback(_prepared(['a', 'b', 'c'], start: 0));
    final sender = _sender();
    final cast = await _connected(playback, sender);
    sender.reportPlaying(
      position: const Duration(seconds: 8),
      state: CastPlayerState.paused,
    );
    await _pump();

    await cast.reorder(2, 1);
    await _settle();
    expect(_playNows(sender), 1);

    await cast.play();
    await _pump();
    expect(_playNows(sender), 2);
    expect(sender.lastOptions('PlayNow')['startPositionTicks'], 80000000);
    expect(_receiverUpcoming(sender), ['a', 'c', 'b']);
    expect(cast.remotePlaying, isTrue);
  });

  test('replacing upcoming keeps the current track and position', () async {
    final playback = _QueuePlayback(_prepared(['a', 'b', 'c', 'd'], start: 1));
    final sender = _sender();
    final cast = await _connected(playback, sender);

    await cast.replaceUpcoming([_track('r1'), _track('r2')]);
    await _settle();

    expect(cast.remoteTrack?.id, 'b');
    expect(cast.castQueue.map((track) => track.id), ['a', 'b', 'r1', 'r2']);
    expect(_receiverUpcoming(sender), ['b', 'r1', 'r2']);
  });

  test(
    'the receiver follows the phone when an edit is still pending',
    () async {
      final playback = _QueuePlayback(_prepared(['a', 'b', 'c'], start: 0));
      final sender = _sender();
      final cast = await _connected(playback, sender);

      await cast.removeAt(1);
      sender.finishCurrent();
      await _settle();

      expect(cast.remoteTrack?.id, 'c');
      expect(sender.playingItemId, 'c');
      expect(_receiverUpcoming(sender), ['c']);
    },
  );

  test('removing the current entry plays its successor paused-aware', () async {
    final playback = _QueuePlayback(_prepared(['a', 'b', 'c'], start: 1));
    final sender = _sender();
    final cast = await _connected(playback, sender);
    sender.reportPlaying(
      position: const Duration(seconds: 9),
      state: CastPlayerState.paused,
    );
    await _pump();

    await cast.removeAt(1);
    await _pump();

    expect(sender.playingItemId, 'c');
    expect(sender.calls.last, 'pause');
    expect(cast.castQueue.map((track) => track.id), ['a', 'c']);
    expect(cast.remoteTrack?.id, 'c');
    expect(playback.localPlayCalls, 0);
  });

  test(
    'removing the final entry stops the receiver and keeps casting',
    () async {
      final playback = _QueuePlayback(_prepared(['a'], start: 0));
      final sender = _sender();
      final cast = await _connected(playback, sender);

      await cast.removeAt(0);
      await _pump();

      expect(sender.stopCalls, 1);
      expect(cast.castQueue, isEmpty);
      expect(cast.ownership, CastOwnership.remote);
      expect(sender.connectionState, CastConnectionState.connected);

      await cast.replaceQueue([_track('n')], startIndex: 0);
      await _pump();
      expect(cast.castQueue.map((track) => track.id), ['n']);
      expect(cast.remoteTrack?.id, 'n');
      expect(sender.playingItemId, 'n');
    },
  );

  test('history selection inserts next and updates history', () async {
    final playback = _QueuePlayback(_prepared(['a', 'b', 'c'], start: 0));
    final sender = _sender();
    final cast = await _connected(playback, sender);

    await cast.playHistoryTrack(_track('h'));
    await _pump();

    expect(sender.playingItemId, 'h');
    expect(cast.castQueue.map((track) => track.id), ['a', 'h', 'b', 'c']);
    expect(cast.remoteTrack?.id, 'h');
    expect(cast.castHistory.map((track) => track.id), ['a']);
    expect(playback.localPlayCalls, 0);
  });

  test('shuffle keeps the current track and reorders the receiver', () async {
    final playback = _QueuePlayback(
      _prepared(['a', 'b', 'c', 'd', 'e'], start: 1),
    );
    final sender = _sender();
    final cast = await _connected(playback, sender);

    await cast.toggleShuffle();
    await _settle();

    expect(cast.remoteTrack?.id, 'b');
    expect(cast.castShuffle, isTrue);
    expect(cast.castQueue.first.id, 'a');
    expect(cast.castQueue.map((track) => track.id).toSet(), {
      'a',
      'b',
      'c',
      'd',
      'e',
    });
    expect(_receiverUpcoming(sender), _upcoming(cast));
  });

  test('commands are rejected while not remote', () async {
    final playback = _QueuePlayback(_prepared(['a', 'b'], start: 0));
    final sender = _sender();
    final cast = _controller(playback, sender);
    await cast.configure(_session);

    await expectLater(
      cast.addToQueue(_track('x')),
      throwsA(isA<CastException>()),
    );
    expect(sender.commands, isEmpty);

    await cast.connect(_device);
    await _pump();
    await cast.handleAppBackground();
    sender.emitConnection(CastConnectionState.disconnected);
    await _pump();
    expect(cast.ownership, CastOwnership.recovering);

    await expectLater(cast.removeAt(0), throwsA(isA<CastException>()));
    expect(cast.castQueue.map((track) => track.id), ['a', 'b']);
    expect(playback.localPlayCalls, 0);
  });

  test('a failed selection keeps the prior state', () async {
    final playback = _QueuePlayback(_prepared(['a', 'b', 'c'], start: 0));
    final sender = _sender();
    final cast = await _connected(playback, sender);
    sender.failCommandCount = 1;

    await expectLater(cast.playIndex(2), throwsA(isA<CastException>()));
    await _pump();

    expect(cast.remoteTrack?.id, 'a');
    expect(cast.ownership, CastOwnership.remote);
    expect(cast.error, isNotNull);
    expect(playback.localPlayCalls, 0);

    sender.reportPlaying(position: const Duration(seconds: 5));
    await _pump();
    expect(cast.remotePosition, const Duration(seconds: 5));

    await cast.playIndex(2);
    await _pump();
    expect(cast.remoteTrack?.id, 'c');
  });

  test('duplicate tracks keep distinct occurrences', () async {
    final playback = _QueuePlayback(_prepared(['a', 'b', 'a'], start: 0));
    final sender = _sender();
    final cast = await _connected(playback, sender);

    await cast.playIndex(2);
    await _pump();
    expect(sender.lastOptions('PlayNow')['startIndex'], 2);
    expect(cast.remoteIndex, 2);

    await cast.removeTrack('a');
    await _pump();
    expect(cast.castQueue.map((track) => track.id), ['b']);
  });

  test('edits survive disconnect into the resumed snapshot', () async {
    final playback = _QueuePlayback(_prepared(['a', 'b'], start: 0));
    final sender = _sender();
    final cast = await _connected(playback, sender);

    await cast.addToQueue(_track('c'));
    await _pump();
    await cast.disconnect();
    await _pump();

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

  test('a long queue is topped up as the receiver nears its end', () async {
    _ids = 1000;
    final local = QueueState.prepare(
      [for (var i = 0; i < 250; i++) _track('t-$i')],
      startIndex: 120,
      shuffle: false,
      newId: _newId,
    );
    final playback = _QueuePlayback(local);
    final sender = _sender();
    final cast = await _connected(playback, sender);

    expect(cast.castQueue, hasLength(100));
    expect(cast.remoteTrack?.id, 't-120');
    expect(sender.playlist.last, 't-199');

    for (var i = 0; i < 70; i++) {
      sender.finishCurrent();
      await _pump();
    }
    await _settle();

    expect(cast.remoteTrack?.id, 't-190');
    expect(sender.commandNames, contains('PlayLast'));
    expect(sender.playlist.last, 't-249');
    expect(_playNows(sender), 1);
    expect(playback.localPlayCalls, 0);
  });
}
