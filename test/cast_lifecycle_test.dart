import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/services/cast/cast_controller.dart';
import 'package:spotifin/services/cast/cast_device.dart';
import 'package:spotifin/services/cast/cast_playback_source.dart';
import 'package:spotifin/services/cast/cast_sender.dart';
import 'package:spotifin/services/cast/playback_service_cast_source.dart';
import 'package:spotifin/services/jellyfin/session.dart';
import 'package:spotifin/services/playback/playback_service.dart';
import 'package:spotifin/services/playback/playback_snapshot.dart';
import 'package:spotifin/services/playback/queue_state.dart';
import 'package:spotifin/storage/database.dart';

import 'support/fake_receiver_sender.dart';
import 'support/playback_harness.dart';

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

class _FakePlayback implements CastPlaybackSource {
  _FakePlayback({required List<Track> queue}) : _queue = List.of(queue);

  final List<Track> _queue;
  final int _index = 0;
  final Duration _position = const Duration(seconds: 12);
  final bool _playing = true;
  bool castingActive = false;
  final restoredSnapshots = <PlaybackSnapshot>[];
  int reportCalls = 0;
  int _ids = 0;

  @override
  Track? get currentTrack =>
      _queue.isEmpty ? null : _queue[_index.clamp(0, _queue.length - 1)];

  @override
  List<Track> get queue => List.unmodifiable(_queue);

  @override
  int? get currentIndex => _queue.isEmpty ? null : _index;

  @override
  Duration get position => _position;

  @override
  bool get playing => _playing;

  @override
  Future<void> stopForCast() async {}

  @override
  Future<void> playQueueIndex(int index) async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  void setCastingActive(bool active) {
    castingActive = active;
  }

  @override
  PlaybackSnapshot captureSnapshot() => PlaybackSnapshot(
    queue: QueueState.restore(
      _queue,
      index: _queue.isEmpty ? 0 : _index.clamp(0, _queue.length - 1),
      shuffle: false,
      newId: () => 'fake-${_ids++}',
    ),
    position: _position,
    playing: _playing,
    repeatMode: LoopMode.off,
    history: const [],
  );

  @override
  Future<void> restoreSnapshot(PlaybackSnapshot snapshot) async {
    restoredSnapshots.add(snapshot);
  }

  @override
  Future<void> reportCurrentState() async {
    reportCalls++;
  }
}

CastController _controller({
  required CastPlaybackSource playback,
  required FakeReceiverSender sender,
}) => CastController(
  playback: playback,
  sender: sender,
  isSupported: () => true,
  sessionLossGrace: const Duration(seconds: 30),
  adoptTimeout: const Duration(milliseconds: 10),
);

FakeReceiverSender _sender() => FakeReceiverSender(devices: const [_device]);

Duration? _lastStart(FakeReceiverSender sender) {
  final ticks = sender.lastOptions('PlayNow')['startPositionTicks'] as int?;
  return ticks == null ? null : Duration(microseconds: ticks ~/ 10);
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  group('failed handoff with real playback', () {
    test('paused state restores without starting audio', () async {
      final harness = PlaybackHarness();
      addTearDown(harness.dispose);
      await harness.configure();
      await harness.service.replaceQueue(playbackCatalog(3), startIndex: 1);
      await harness.service.pause();
      await harness.settle();

      final sender = _sender()..failCommandCount = 10;
      final cast = _controller(
        playback: PlaybackServiceCastSource(harness.service),
        sender: sender,
      );
      addTearDown(sender.dispose);
      addTearDown(cast.dispose);
      await cast.configure(_session);

      await expectLater(cast.connect(_device), throwsA(isA<CastException>()));

      expect(cast.ownership, CastOwnership.local);
      expect(cast.isCasting, isFalse);
      expect(cast.error, isNotNull);
      expect(harness.service.isCastingActive, isFalse);
      expect(harness.service.queue.map((track) => track.id), [
        'track-0',
        'track-1',
        'track-2',
      ]);
      expect(harness.service.currentTrack?.id, 'track-1');
      expect(harness.service.playing, isFalse);
      expect(harness.player.playCalls, 1);
      expect(sender.stopCalls, greaterThanOrEqualTo(1));
    });

    test('playing state resumes playing locally', () async {
      final harness = PlaybackHarness();
      addTearDown(harness.dispose);
      await harness.configure();
      await harness.service.replaceQueue(playbackCatalog(3), startIndex: 1);
      await harness.settle();
      expect(harness.service.playing, isTrue);

      final sender = _sender()..failCommandCount = 10;
      final cast = _controller(
        playback: PlaybackServiceCastSource(harness.service),
        sender: sender,
      );
      addTearDown(sender.dispose);
      addTearDown(cast.dispose);
      await cast.configure(_session);

      await expectLater(cast.connect(_device), throwsA(isA<CastException>()));

      expect(cast.ownership, CastOwnership.local);
      expect(harness.service.currentTrack?.id, 'track-1');
      expect(harness.service.playing, isTrue);
      expect(harness.player.playCalls, 2);
    });
  });

  group('recovery across transport resets', () {
    test('empty remote before disconnect keeps the position', () async {
      final playback = _FakePlayback(queue: [_track('a'), _track('b')]);
      final sender = _sender();
      final cast = _controller(playback: playback, sender: sender);
      addTearDown(sender.dispose);
      addTearDown(cast.dispose);
      await cast.configure(_session);
      await cast.connect(_device);
      expect(cast.ownership, CastOwnership.remote);

      sender.emitRemote(const CastRemoteState());
      await _pump();
      sender.emitConnection(CastConnectionState.disconnected);
      await _pump();

      expect(cast.ownership, CastOwnership.recovering);
      expect(cast.error, isNull);

      await cast.retry();
      await cast.play();
      await _pump();
      expect(sender.calls, contains('connect:room'));
      expect(_lastStart(sender), const Duration(seconds: 12));
    });

    test('disconnect before empty remote keeps the position', () async {
      final playback = _FakePlayback(queue: [_track('a'), _track('b')]);
      final sender = _sender();
      final cast = _controller(playback: playback, sender: sender);
      addTearDown(sender.dispose);
      addTearDown(cast.dispose);
      await cast.configure(_session);
      await cast.connect(_device);

      sender.emitConnection(CastConnectionState.disconnected);
      await _pump();
      sender.emitRemote(const CastRemoteState());
      await _pump();

      expect(cast.ownership, CastOwnership.recovering);

      await cast.retry();
      await cast.play();
      await _pump();
      expect(_lastStart(sender), const Duration(seconds: 12));
    });

    test('paused recovery survives reset and retry stays paused', () async {
      final playback = _FakePlayback(queue: [_track('a'), _track('b')]);
      final sender = _sender();
      final cast = _controller(playback: playback, sender: sender);
      addTearDown(sender.dispose);
      addTearDown(cast.dispose);
      await cast.configure(_session);
      await cast.connect(_device);

      sender.reportPlaying(
        position: const Duration(seconds: 30),
        state: CastPlayerState.paused,
      );
      await _pump();
      sender.emitRemote(const CastRemoteState());
      await _pump();
      sender.emitConnection(CastConnectionState.disconnected);
      await _pump();

      await cast.retry();
      await _settle();
      expect(cast.remotePlaying, isFalse);
      expect(cast.remotePosition, const Duration(seconds: 30));

      await cast.disconnect();
      await _pump();
      expect(playback.restoredSnapshots, hasLength(1));
      expect(
        playback.restoredSnapshots.single.position,
        const Duration(seconds: 30),
      );
      expect(playback.restoredSnapshots.single.playing, isFalse);
    });

    test('buffering never flips a playing decision', () async {
      final playback = _FakePlayback(queue: [_track('a')]);
      final sender = _sender();
      final cast = _controller(playback: playback, sender: sender);
      addTearDown(sender.dispose);
      addTearDown(cast.dispose);
      await cast.configure(_session);
      await cast.connect(_device);

      sender.reportPlaying(
        position: const Duration(seconds: 40),
        state: CastPlayerState.buffering,
      );
      await _pump();
      sender.emitConnection(CastConnectionState.disconnected);
      await _pump();

      await cast.retry();
      await cast.play();
      await _settle();
      expect(_lastStart(sender), const Duration(seconds: 40));
      expect(cast.remotePlaying, isTrue);
    });
  });

  group('lifecycle invalidation with real playback', () {
    test('sign-out during delayed connect defeats the handoff', () async {
      final harness = PlaybackHarness();
      addTearDown(harness.dispose);
      await harness.configure();
      await harness.service.replaceQueue(playbackCatalog(3), startIndex: 0);
      await harness.settle();

      final sender = _sender()..connectGate = Completer<void>();
      final cast = _controller(
        playback: PlaybackServiceCastSource(harness.service),
        sender: sender,
      );
      addTearDown(sender.dispose);
      addTearDown(cast.dispose);
      await cast.configure(_session);

      final connecting = cast.connect(_device);
      await _pump();
      expect(cast.ownership, CastOwnership.local);
      final cleaning = cast.configure(null);
      await _pump();
      sender.connectGate?.complete();
      await connecting;
      await cleaning;
      await _pump();

      expect(sender.commands, isEmpty);
      expect(cast.ownership, CastOwnership.local);
      expect(cast.isCasting, isFalse);
      expect(harness.player.playCalls, 1);
    });

    test('sign-out during delayed load discards without restoring', () async {
      final harness = PlaybackHarness();
      addTearDown(harness.dispose);
      await harness.configure();
      await harness.service.replaceQueue(playbackCatalog(3), startIndex: 0);
      await harness.settle();

      final sender = _sender()..commandGate = Completer<void>();
      final cast = _controller(
        playback: PlaybackServiceCastSource(harness.service),
        sender: sender,
      );
      addTearDown(sender.dispose);
      addTearDown(cast.dispose);
      await cast.configure(_session);

      final connecting = cast.connect(_device);
      await _pump();
      final cleaning = cast.configure(null);
      await _pump();
      sender.commandGate?.complete();
      await connecting;
      await cleaning;
      await _pump();

      expect(sender.commandNames, isNot(contains('PlayNow')));
      expect(cast.ownership, CastOwnership.local);
      expect(cast.isCasting, isFalse);
      expect(harness.service.isCastingActive, isFalse);
      // The old local queue is untouched; no stale snapshot was restored
      // into a signed-out account.
      expect(harness.service.queue.map((track) => track.id), [
        'track-0',
        'track-1',
        'track-2',
      ]);
    });

    test('failed receiver stop retains recovery without local audio', () async {
      final harness = PlaybackHarness();
      addTearDown(harness.dispose);
      await harness.configure();
      await harness.service.replaceQueue(playbackCatalog(3), startIndex: 0);
      await harness.settle();

      final sender = _sender();
      final cast = _controller(
        playback: PlaybackServiceCastSource(harness.service),
        sender: sender,
      );
      addTearDown(sender.dispose);
      addTearDown(cast.dispose);
      await cast.configure(_session);
      await cast.connect(_device);
      expect(cast.ownership, CastOwnership.remote);

      sender.failDisconnect = true;
      await expectLater(cast.disconnect(), throwsA(isA<CastException>()));

      expect(cast.ownership, CastOwnership.recovering);
      expect(cast.isCasting, isTrue);
      expect(harness.service.isCastingActive, isTrue);
      expect(harness.player.playCalls, 1);
      expect(harness.service.queue.map((track) => track.id), [
        'track-0',
        'track-1',
        'track-2',
      ]);
    });

    test(
      'resume restores the handoff snapshot after local replacement',
      () async {
        final harness = PlaybackHarness();
        addTearDown(harness.dispose);
        await harness.configure();
        await harness.service.replaceQueue(playbackCatalog(5), startIndex: 0);
        await harness.settle();

        final sender = _sender();
        final cast = _controller(
          playback: PlaybackServiceCastSource(harness.service),
          sender: sender,
        );
        addTearDown(sender.dispose);
        addTearDown(cast.dispose);
        await cast.configure(_session);
        await cast.connect(_device);
        expect(cast.ownership, CastOwnership.remote);

        await harness.service.replaceQueue(playbackCatalog(2), startIndex: 1);
        await harness.settle();

        await cast.disconnect();
        await harness.settle();

        expect(cast.ownership, CastOwnership.local);
        expect(harness.service.queue.map((track) => track.id), [
          'track-0',
          'track-1',
          'track-2',
          'track-3',
          'track-4',
        ]);
        expect(harness.service.currentTrack?.id, 'track-0');
      },
    );
  });

  test('disposal during a delayed operation notifies nothing after', () async {
    final playback = _FakePlayback(queue: [_track('a')]);
    final sender = _sender()..connectGate = Completer<void>();
    final cast = _controller(playback: playback, sender: sender);

    var notified = 0;
    cast.addListener(() => notified++);
    await cast.configure(_session);

    final connecting = cast.connect(_device);
    await _pump();
    final during = notified;
    expect(during, greaterThan(0));

    cast.dispose();
    sender.connectGate?.complete();
    await connecting;
    await _pump();
    expect(notified, during);
    sender.dispose();
  });

  test('sender has one disposal owner and no discovery on build', () async {
    final sender = _sender();
    final mockPlayback = _MockPlaybackService();
    final container = ProviderContainer(
      overrides: [
        playbackProvider.overrideWithValue(mockPlayback),
        castSenderProvider.overrideWith((ref) {
          ref.onDispose(sender.dispose);
          return sender;
        }),
      ],
    );

    final controller = container.read(castControllerProvider);
    expect(controller.ownership, CastOwnership.local);
    expect(sender.initializeCalls, 0);
    expect(sender.startDiscoveryCalls, 0);

    container.dispose();
    expect(sender.disposeCalls, 1);
    verifyNever(() => mockPlayback.dispose());
  });
}

class _MockPlaybackService extends Mock implements PlaybackService {}
