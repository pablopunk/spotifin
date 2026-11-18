import 'dart:async';

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

class FakePlayback implements CastPlaybackSource {
  FakePlayback({
    required List<Track> queue,
    int index = 0,
    this.repeatMode = LoopMode.off,
  }) : _queue = List.of(queue),
       // ignore: prefer_initializing_formals
       _index = index;

  List<Track> _queue;
  int _index;
  final LoopMode repeatMode;
  Duration _position = const Duration(seconds: 12);
  bool castingActive = false;
  bool _playing = true;
  int stopForCastCalls = 0;
  final playIndexCalls = <int>[];
  final seekCalls = <Duration>[];
  int playCalls = 0;
  int pauseCalls = 0;
  final restoredSnapshots = <PlaybackSnapshot>[];
  int reportCurrentStateCalls = 0;

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
  bool get playing => _playing;

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
    _playing = true;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _playing = false;
  }

  @override
  void setCastingActive(bool active) {
    castingActive = active;
  }

  int _snapshotIds = 0;

  @override
  PlaybackSnapshot captureSnapshot() => PlaybackSnapshot(
    queue: QueueState.restore(
      _queue,
      index: _queue.isEmpty ? 0 : _index.clamp(0, _queue.length - 1),
      shuffle: false,
      newId: () => 'local-${_snapshotIds++}',
    ),
    position: _position,
    playing: _playing,
    repeatMode: repeatMode,
    history: const [],
  );

  @override
  Future<void> restoreSnapshot(PlaybackSnapshot snapshot) async {
    restoredSnapshots.add(snapshot);
    _queue = [for (final entry in snapshot.queue.loadedEntries) entry.track];
    _index = (snapshot.queue.currentIndex ?? 0).clamp(
      0,
      _queue.isEmpty ? 0 : _queue.length - 1,
    );
    _position = snapshot.position;
    _playing = snapshot.playing;
  }

  @override
  Future<void> reportCurrentState() async {
    reportCurrentStateCalls++;
  }
}

CastController controller({
  required FakePlayback playback,
  required FakeReceiverSender sender,
  JellyfinSession? session = httpsSession,
  bool supported = true,
  Duration sessionLossGrace = const Duration(milliseconds: 5),
}) {
  final instance = CastController(
    playback: playback,
    sender: sender,
    isSupported: () => supported,
    sessionLossGrace: sessionLossGrace,
    resyncDelay: const Duration(milliseconds: 1),
    adoptTimeout: const Duration(milliseconds: 20),
  );
  instance.configure(session);
  addTearDown(sender.dispose);
  addTearDown(instance.dispose);
  return instance;
}

const livingRoom = CastDevice(id: 'room', friendlyName: 'Living Room');

Future<void> pump() => Future<void>.delayed(Duration.zero);

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

Future<CastController> casting(
  List<String> ids, {
  int index = 0,
  LoopMode repeatMode = LoopMode.off,
  FakeReceiverSender? sender,
  FakePlayback? playback,
}) async {
  final cast = controller(
    playback:
        playback ??
        FakePlayback(
          queue: [for (final id in ids) track(id)],
          index: index,
          repeatMode: repeatMode,
        ),
    sender: sender ?? FakeReceiverSender(devices: const [livingRoom]),
  );
  await cast.connect(livingRoom);
  await pump();
  expect(cast.ownership, CastOwnership.remote);
  return cast;
}

void main() {
  group('handoff', () {
    test('sends the whole queue to the receiver with credentials', () async {
      final playback = FakePlayback(
        queue: [track('a'), track('b'), track('c')],
        index: 1,
      );
      final sender = FakeReceiverSender(devices: const [livingRoom]);
      final cast = controller(playback: playback, sender: sender);

      await cast.initialize();
      expect(cast.devices.map((d) => d.id), ['room']);
      await cast.connect(livingRoom);
      await pump();

      expect(sender.initializedAppId, 'F007D354');
      expect(sender.commandNames, ['SetRepeatMode', 'PlayNow']);
      final playNow = sender.lastCommand('PlayNow');
      expect(playNow['serverAddress'], 'https://music.example.com/jellyfin');
      expect(playNow['accessToken'], 'token');
      expect(playNow['userId'], 'user');
      final options = sender.lastOptions('PlayNow');
      expect(sender.itemIdsOf(options), ['a', 'b', 'c']);
      expect(options['startIndex'], 1);
      expect(options['startPositionTicks'], 120000000);

      expect(cast.isCasting, isTrue);
      expect(cast.remoteTrack?.id, 'b');
      expect(cast.remotePlaying, isTrue);
      expect(playback.stopForCastCalls, 1);
      expect(playback.castingActive, isTrue);
      expect(playback.queue.map((t) => t.id), ['a', 'b', 'c']);
    });

    test('hands the repeat mode to the receiver', () async {
      final sender = FakeReceiverSender(devices: const [livingRoom]);
      await casting(['a', 'b'], repeatMode: LoopMode.all, sender: sender);
      expect(sender.repeatMode, 'RepeatAll');
    });

    test('waits for the receiver before handing off playback', () async {
      final playback = FakePlayback(queue: [track('a')]);
      final sender = FakeReceiverSender(devices: const [livingRoom])
        ..connectStaysConnecting = true;
      final cast = controller(playback: playback, sender: sender);

      final connecting = cast.connect(livingRoom);
      await pump();
      expect(cast.connectionState, CastConnectionState.connecting);
      expect(sender.commands, isEmpty);
      expect(playback.stopForCastCalls, 0);

      sender.emitConnection(CastConnectionState.connected, livingRoom);
      await connecting;
      expect(cast.isCasting, isTrue);
      expect(sender.commandNames, contains('PlayNow'));
    });

    test('failed handoff surfaces and resumes local playback', () async {
      final playback = FakePlayback(queue: [track('a')]);
      final sender = FakeReceiverSender(devices: const [livingRoom])
        ..failCommandCount = 10;
      final cast = controller(playback: playback, sender: sender);

      await expectLater(
        cast.connect(livingRoom),
        throwsA(isA<CastException>()),
      );
      expect(cast.isCasting, isFalse);
      expect(cast.ownership, CastOwnership.local);
      expect(cast.error, isNotNull);
      expect(playback.castingActive, isFalse);
      expect(playback.restoredSnapshots, hasLength(1));
    });

    test('follows receiver volume instead of starting at full', () async {
      final sender = FakeReceiverSender(devices: const [livingRoom])
        ..emitRemote(const CastRemoteState(volume: 0.3));
      final cast = await casting(['a'], sender: sender);
      expect(cast.remoteVolume, 0.3);

      sender.emitRemote(sender.remoteState.copyWith(volume: 0.6));
      await pump();
      expect(cast.remoteVolume, 0.6);
    });
  });

  group('receiver-owned queue', () {
    test(
      'keeps playing the queue without the phone sending anything',
      () async {
        final sender = FakeReceiverSender(devices: const [livingRoom]);
        final cast = await casting(['a', 'b', 'c'], sender: sender);
        final sent = sender.commands.length;

        sender.finishCurrent();
        await pump();
        expect(cast.remoteTrack?.id, 'b');
        expect(cast.remoteIndex, 1);

        sender.finishCurrent();
        await pump();
        expect(cast.remoteTrack?.id, 'c');
        expect(cast.remotePlaying, isTrue);
        expect(sender.commands, hasLength(sent));
      },
    );

    test('duplicate tracks resolve to the occurrence reached', () async {
      final sender = FakeReceiverSender(devices: const [livingRoom]);
      final cast = await casting(['a', 'b', 'a'], sender: sender);

      sender.finishCurrent();
      await pump();
      sender.finishCurrent();
      await pump();

      expect(cast.remoteTrack?.id, 'a');
      expect(cast.remoteIndex, 2);
    });

    test('repeat all wraps with the receiver', () async {
      final sender = FakeReceiverSender(devices: const [livingRoom]);
      final cast = await casting(
        ['a', 'b'],
        repeatMode: LoopMode.all,
        sender: sender,
      );
      sender.finishCurrent();
      await pump();
      sender.finishCurrent();
      await pump();
      expect(cast.remoteIndex, 0);
      expect(cast.remoteTrack?.id, 'a');
    });

    test(
      'queue end leaves the last track paused; play starts it again',
      () async {
        final sender = FakeReceiverSender(devices: const [livingRoom]);
        final cast = await casting(['a', 'b'], index: 1, sender: sender);

        sender.finishCurrent();
        await pump();
        expect(cast.remoteTrack?.id, 'b');
        expect(cast.remotePlaying, isFalse);
        expect(cast.error, isNull);

        await cast.play();
        await pump();
        expect(sender.lastOptions('PlayNow')['startPositionTicks'], isNull);
        expect(sender.playingItemId, 'b');
        expect(cast.remotePlaying, isTrue);
      },
    );

    test('next uses the receiver queue when it is in sync', () async {
      final sender = FakeReceiverSender(devices: const [livingRoom]);
      final cast = await casting(['a', 'b', 'c'], sender: sender);

      await cast.next();
      await pump();
      expect(sender.commandNames.last, 'NextTrack');
      expect(cast.remoteTrack?.id, 'b');
      expect(sender.playingItemId, 'b');
    });

    test('next skips even when the receiver repeats one track', () async {
      final sender = FakeReceiverSender(devices: const [livingRoom]);
      final cast = await casting(
        ['a', 'b'],
        repeatMode: LoopMode.one,
        sender: sender,
      );
      await cast.next();
      await pump();
      expect(cast.remoteTrack?.id, 'b');
      expect(sender.playingItemId, 'b');
    });

    test('next at the end wraps under repeat all', () async {
      final sender = FakeReceiverSender(devices: const [livingRoom]);
      final cast = await casting(
        ['a', 'b'],
        index: 1,
        repeatMode: LoopMode.all,
        sender: sender,
      );
      await cast.next();
      await pump();
      expect(cast.remoteIndex, 0);
      expect(sender.playingItemId, 'a');
    });

    test('status from the previous item never moves the queue back', () async {
      final sender = FakeReceiverSender(devices: const [livingRoom]);
      final cast = await casting(['a', 'b', 'c'], sender: sender);
      sender.commandGate = Completer<void>();

      final jumping = cast.playIndex(2);
      await pump();
      sender.emitRemote(
        const CastRemoteState(
          playerState: CastPlayerState.playing,
          position: Duration(seconds: 50),
          itemId: 'a',
        ),
      );
      await pump();
      expect(cast.remoteTrack?.id, 'a');
      expect(cast.remotePosition, Duration.zero);

      sender.commandGate!.complete();
      sender.commandGate = null;
      await jumping;
      await pump();
      expect(cast.remoteTrack?.id, 'c');
    });

    test('previous restarts late in a track and goes back early', () async {
      final sender = FakeReceiverSender(devices: const [livingRoom]);
      final cast = await casting(['a', 'b', 'c'], index: 1, sender: sender);

      sender.reportPlaying(position: const Duration(seconds: 30));
      await pump();
      await cast.previous();
      expect(sender.commandNames.last, 'Seek');
      expect(sender.lastOptions('Seek')['position'], 0);
      expect(cast.remoteTrack?.id, 'b');

      sender.reportPlaying(position: const Duration(seconds: 2));
      await pump();
      await cast.previous();
      await pump();
      expect(cast.remoteTrack?.id, 'a');
      expect(sender.playingItemId, 'a');
    });

    test('transport controls drive the receiver', () async {
      final sender = FakeReceiverSender(devices: const [livingRoom]);
      final cast = await casting(['a', 'b'], sender: sender);

      await cast.toggle();
      expect(sender.calls, contains('pause'));
      await cast.toggle();
      expect(sender.calls, contains('play'));

      await cast.seek(const Duration(seconds: 30));
      expect(sender.lastOptions('Seek')['position'], 30);

      await cast.setVolume(2.5);
      expect(sender.calls.last, 'volume:1.0');
    });

    test('next at the end of the queue is an explicit error', () async {
      final cast = await casting(['a']);
      await expectLater(cast.next(), throwsA(isA<CastException>()));
      expect(cast.error, contains('end of the queue'));
    });

    test('receiver playback errors are surfaced', () async {
      final sender = FakeReceiverSender(devices: const [livingRoom]);
      final cast = await casting(['a'], sender: sender);

      sender.emitReceiverMessage({
        'type': 'playbackerror',
        'message': 'NoCompatibleStream',
      });
      await pump();
      expect(cast.error, contains('can\u2019t play on Chromecast'));
    });
  });

  group('connection drops', () {
    test('a resumed session is adopted without reloading', () async {
      final sender = FakeReceiverSender(devices: const [livingRoom]);
      final cast = controller(
        playback: FakePlayback(queue: [track('a'), track('b'), track('c')]),
        sender: sender,
        sessionLossGrace: const Duration(seconds: 30),
      );
      await cast.connect(livingRoom);
      final sent = sender.commands.length;

      sender.emitConnection(CastConnectionState.disconnected);
      await pump();
      expect(cast.ownership, CastOwnership.recovering);
      expect(cast.isCasting, isTrue);
      expect(cast.error, isNull);
      expect(cast.connectedDeviceName, 'Living Room');
      expect(cast.remoteTrack?.id, 'a');
      expect(cast.remotePosition, const Duration(seconds: 12));

      // The phone slept while the receiver kept going.
      sender.index = 1;
      sender.emitConnection(CastConnectionState.connected, livingRoom);
      sender.reportPlaying(position: const Duration(seconds: 40));
      await settle();

      expect(cast.ownership, CastOwnership.remote);
      expect(cast.remoteTrack?.id, 'b');
      expect(cast.remotePosition, const Duration(seconds: 40));
      expect(sender.commands.skip(sent).map((c) => c['command']), [
        'SetRepeatMode',
      ]);
      expect(cast.error, isNull);
    });

    test('a session ended elsewhere returns to the phone paused', () async {
      final playback = FakePlayback(queue: [track('a'), track('b')]);
      final sender = FakeReceiverSender(devices: const [livingRoom]);
      final cast = await casting(const [], playback: playback, sender: sender);
      sender.finishCurrent();
      sender.reportPlaying(position: const Duration(seconds: 20));
      await pump();
      sender.calls.clear();

      sender.emitConnection(CastConnectionState.disconnected);
      await settle();

      expect(sender.calls, isNot(contains('connect:room')));
      expect(cast.ownership, CastOwnership.local);
      expect(cast.error, contains('Casting to Living Room ended'));
      final restored = playback.restoredSnapshots.single;
      expect(restored.queue.currentIndex, 1);
      expect(restored.position, const Duration(seconds: 20));
      expect(restored.playing, isFalse);
      expect(playback.castingActive, isFalse);
    });

    test('a receiver that lost the queue never restarts by itself', () async {
      final sender = FakeReceiverSender(devices: const [livingRoom]);
      final cast = controller(
        playback: FakePlayback(queue: [track('a'), track('b')]),
        sender: sender,
        sessionLossGrace: const Duration(seconds: 30),
      );
      await cast.connect(livingRoom);
      sender.reportPlaying(position: const Duration(seconds: 30));
      await pump();

      sender.emitConnection(CastConnectionState.disconnected);
      sender.playlist = [];
      sender.index = -1;
      sender.emitConnection(CastConnectionState.connected, livingRoom);
      await settle();

      expect(cast.ownership, CastOwnership.remote);
      expect(sender.commandNames.where((c) => c == 'PlayNow'), hasLength(1));
      expect(cast.remotePlaying, isFalse);
      expect(cast.remoteTrack?.id, 'a');
      expect(cast.remotePosition, const Duration(seconds: 30));

      await cast.play();
      await pump();
      final options = sender.lastOptions('PlayNow');
      expect(options['startPositionTicks'], 300000000);
      expect(sender.playingItemId, 'a');
    });

    test('the loss timer waits while the app is in the background', () async {
      final sender = FakeReceiverSender(devices: const [livingRoom]);
      final cast = await casting(['a'], sender: sender);
      await cast.handleAppBackground();

      sender.emitConnection(CastConnectionState.disconnected);
      await settle();
      expect(cast.ownership, CastOwnership.recovering);

      sender.emitConnection(CastConnectionState.connected, livingRoom);
      sender.reportPlaying(position: const Duration(seconds: 3));
      await cast.handleAppForeground();
      await settle();
      expect(cast.ownership, CastOwnership.remote);
      expect(cast.error, isNull);
    });

    test('retry reconnects to the last device', () async {
      final sender = FakeReceiverSender(devices: const [livingRoom]);
      final cast = controller(
        playback: FakePlayback(queue: [track('a')]),
        sender: sender,
        sessionLossGrace: const Duration(seconds: 30),
      );
      await cast.connect(livingRoom);
      sender.emitConnection(CastConnectionState.disconnected);
      await pump();

      await cast.retry();
      await settle();
      expect(sender.calls, contains('connect:room'));
      expect(cast.ownership, CastOwnership.remote);
    });

    test('device list changes never end casting', () async {
      final sender = FakeReceiverSender(devices: const [livingRoom]);
      final cast = await casting(['a'], sender: sender);
      sender.setDevices(const [CastDevice(id: 'other', friendlyName: 'Other')]);
      await pump();
      expect(cast.error, isNull);
      expect(cast.ownership, CastOwnership.remote);
    });
  });

  group('stop casting', () {
    test('disconnect resumes locally where the receiver was', () async {
      final playback = FakePlayback(
        queue: [track('a'), track('b'), track('c')],
      );
      final sender = FakeReceiverSender(devices: const [livingRoom]);
      final cast = await casting(const [], playback: playback, sender: sender);
      sender.finishCurrent();
      sender.reportPlaying(position: const Duration(seconds: 25));
      await pump();

      await cast.disconnect();
      await pump();

      expect(sender.stoppedReceiver, isTrue);
      expect(cast.ownership, CastOwnership.local);
      expect(playback.castingActive, isFalse);
      final restored = playback.restoredSnapshots.single;
      expect(restored.queue.currentIndex, 1);
      expect(restored.position, const Duration(seconds: 25));
      expect(restored.playing, isTrue);
      expect(playback.reportCurrentStateCalls, 1);
    });

    test('does not resume locally if stopping the receiver fails', () async {
      final playback = FakePlayback(queue: [track('a')]);
      final sender = FakeReceiverSender(devices: const [livingRoom]);
      final cast = await casting(const [], playback: playback, sender: sender);

      sender.failDisconnect = true;
      await expectLater(cast.disconnect(), throwsA(isA<CastException>()));
      expect(cast.isCasting, isTrue);
      expect(playback.playCalls, 0);
    });
  });

  test('unavailable reasons are explicit', () async {
    final noSession = controller(
      playback: FakePlayback(queue: [track('a')]),
      sender: FakeReceiverSender(),
      session: null,
    );
    expect(noSession.unavailableReason, contains('Sign in'));
    expect(noSession.canCast, isFalse);

    final http = controller(
      playback: FakePlayback(queue: [track('a')]),
      sender: FakeReceiverSender(),
      session: httpSession,
    );
    expect(http.unavailableReason, contains('plain HTTP'));

    final empty = controller(
      playback: FakePlayback(queue: const []),
      sender: FakeReceiverSender(),
    );
    expect(empty.unavailableReason, contains('Nothing playing'));

    final unsupported = controller(
      playback: FakePlayback(queue: [track('a')]),
      sender: FakeReceiverSender(),
      supported: false,
    );
    expect(unsupported.unavailableReason, contains('iPhone and Android'));
    await expectLater(unsupported.castCurrent(), throwsA(isA<CastException>()));
  });
}
