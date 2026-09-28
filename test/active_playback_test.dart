import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/services/cast/cast_controller.dart';
import 'package:spotifin/services/cast/cast_sender.dart';
import 'package:spotifin/services/playback/active_playback.dart';
import 'package:spotifin/services/playback/active_playback_state.dart';
import 'package:spotifin/storage/database.dart';

import 'support/playback_harness.dart';

class _MockCast extends Mock implements CastController {}

Track _track(String id) => Track(
  id: id,
  name: 'Song $id',
  album: 'Album',
  artist: 'Artist',
  artistItems: '[]',
  labels: '[]',
  durationTicks: 1800000000,
  favorite: false,
  playCount: 0,
  normalizationGain: null,
  albumNormalizationGain: null,
  container: 'mp3',
);

void main() {
  setUpAll(() {
    registerFallbackValue(_track('fallback'));
    registerFallbackValue(<Track>[]);
    registerFallbackValue(const Duration(seconds: 1));
    registerFallbackValue(StackTrace.empty);
  });

  group('state observation', () {
    test('builds the initial local snapshot synchronously', () async {
      final harness = PlaybackHarness();
      addTearDown(harness.dispose);
      await harness.configure();
      await harness.service.replaceQueue(playbackCatalog(3), startIndex: 1);
      await harness.settle();

      final cast = _MockCast();
      _stubCastIdle(cast);
      final owner = ActivePlayback(local: harness.service, cast: cast);
      addTearDown(owner.dispose);

      expect(owner.state.destination, PlaybackDestination.local);
      expect(owner.state.track?.id, 'track-1');
      expect(owner.state.index, 1);
      expect(owner.state.entryId, harness.service.currentEntryId);
      expect(owner.state.queue.map((track) => track.id), [
        'track-0',
        'track-1',
        'track-2',
      ]);
      expect(owner.state.upcoming.map((track) => track.id), [
        'track-1',
        'track-2',
      ]);
      expect(owner.state.upcomingOffset, 1);
      expect(owner.state.playing, isTrue);
      expect(owner.state.volumeSlider, 1);
      expect(owner.state.shuffle, isFalse);
      expect(owner.state.repeatMode, LoopMode.off);
      expect(owner.state.busy, isFalse);
      expect(owner.state.recovering, isFalse);
      expect(owner.state.capabilities, PlaybackCapability.values.toSet());
    });

    test('local position updates without a general notification', () async {
      final harness = PlaybackHarness();
      addTearDown(harness.dispose);
      await harness.configure();
      await harness.service.replaceQueue(playbackCatalog(2), startIndex: 0);
      await harness.settle();

      final cast = _MockCast();
      _stubCastIdle(cast);
      final owner = ActivePlayback(local: harness.service, cast: cast);
      addTearDown(owner.dispose);

      var notifications = 0;
      owner.addListener(() => notifications++);
      harness.player.emitPosition(const Duration(seconds: 45));
      await harness.settle();

      expect(owner.state.position, const Duration(seconds: 45));
      expect(notifications, greaterThan(0));
    });

    test('remote updates switch destination and linear volume', () async {
      final harness = PlaybackHarness();
      addTearDown(harness.dispose);
      await harness.configure();

      final cast = _MockCast();
      final castListeners = <VoidCallback>[];
      final positions = StreamController<Duration>.broadcast();
      addTearDown(positions.close);
      _stubCastRemote(cast);
      when(() => cast.positionStream).thenAnswer((_) => positions.stream);
      when(() => cast.addListener(any())).thenAnswer(
        (invocation) => castListeners.add(
          invocation.positionalArguments.single as VoidCallback,
        ),
      );
      when(() => cast.removeListener(any())).thenReturn(null);
      final owner = ActivePlayback(local: harness.service, cast: cast);
      addTearDown(owner.dispose);

      expect(owner.state.destination, PlaybackDestination.cast);
      expect(owner.state.track?.id, 'remote-1');
      expect(owner.state.index, 1);
      expect(owner.state.entryId, 'remote-entry-1');
      expect(owner.state.volumeSlider, 0.3);
      expect(owner.state.shuffle, isTrue);
      expect(owner.state.repeatMode, LoopMode.off);
      expect(owner.state.recovering, isFalse);
      expect(owner.state.capabilities, {
        PlaybackCapability.transport,
        PlaybackCapability.seek,
        PlaybackCapability.volume,
        PlaybackCapability.selection,
        PlaybackCapability.queueEditing,
        PlaybackCapability.shuffle,
      });

      positions.add(const Duration(seconds: 20));
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(owner.state.position, const Duration(seconds: 20));

      for (final listener in List.of(castListeners)) {
        listener();
      }
      expect(owner.state.destination, PlaybackDestination.cast);
    });

    test('loss retains Cast recovery display', () async {
      final harness = PlaybackHarness();
      addTearDown(harness.dispose);
      await harness.configure();

      final cast = _MockCast();
      _stubCastIdle(cast);
      when(() => cast.ownership).thenReturn(CastOwnership.recovering);
      when(() => cast.remotePlaying).thenReturn(false);
      final owner = ActivePlayback(local: harness.service, cast: cast);
      addTearDown(owner.dispose);

      expect(owner.state.destination, PlaybackDestination.cast);
      expect(owner.state.recovering, isTrue);
      expect(owner.state.capabilities, isEmpty);
      await expectLater(
        owner.toggle(),
        throwsA(isA<PlaybackActionUnavailable>()),
      );
    });

    test('disposal keeps borrowed adapters alive', () async {
      final harness = PlaybackHarness();
      addTearDown(harness.dispose);
      await harness.configure();
      await harness.service.replaceQueue(playbackCatalog(2), startIndex: 0);
      await harness.settle();

      final cast = _MockCast();
      _stubCastIdle(cast);
      final owner = ActivePlayback(local: harness.service, cast: cast);
      owner.dispose();

      verify(() => cast.removeListener(any())).called(greaterThanOrEqualTo(1));
      expect(harness.service.queue, hasLength(2));
      expect(harness.player.isDisposed, isFalse);
    });
  });

  group('action routing', () {
    test('local actions reach local playback exactly once', () async {
      final harness = PlaybackHarness();
      addTearDown(harness.dispose);
      await harness.configure();
      await harness.service.replaceQueue(playbackCatalog(4), startIndex: 0);
      await harness.settle();

      final cast = _MockCast();
      _stubCastIdle(cast);
      final owner = ActivePlayback(local: harness.service, cast: cast);
      addTearDown(owner.dispose);

      await owner.pause();
      expect(harness.service.playing, isFalse);
      await owner.play();
      expect(harness.service.playing, isTrue);
      await owner.next();
      expect(harness.service.currentTrack?.id, 'track-1');
      await owner.previous();
      expect(harness.service.currentTrack?.id, 'track-0');
      await owner.seek(const Duration(seconds: 5));
      expect(harness.player.seekPositions.last, const Duration(seconds: 5));
      await owner.setVolumeSlider(0.5);
      expect(harness.service.volume, 0.25);
      expect(owner.state.volumeSlider, closeTo(0.5, 1e-9));
      await owner.toggleShuffle();
      expect(harness.service.shuffle, isTrue);
      final shuffled = harness.service.queue.map((track) => track.id).toList();
      await owner.cycleRepeat();
      expect(harness.service.loopMode, LoopMode.all);
      await owner.addToQueue(playbackTrack(9));
      expect(harness.service.queue.map((track) => track.id).last, 'track-9');
      await owner.removeTrack('track-9');
      expect(harness.service.queue.map((track) => track.id), shuffled);
      await owner.playHistoryTrack(playbackTrack(7));
      expect(harness.service.currentTrack?.id, 'track-7');
      expect(harness.service.queue.map((track) => track.id), [
        shuffled.first,
        'track-7',
        ...shuffled.sublist(1),
      ]);
    });

    test('cast actions reach Cast only with zero local calls', () async {
      final harness = PlaybackHarness();
      addTearDown(harness.dispose);
      await harness.configure();
      await harness.service.replaceQueue(playbackCatalog(3), startIndex: 0);
      await harness.settle();

      final cast = _MockCast();
      _stubCastRemote(cast);
      when(() => cast.toggle()).thenAnswer((_) async {});
      when(() => cast.play()).thenAnswer((_) async {});
      when(() => cast.pause()).thenAnswer((_) async {});
      when(() => cast.next()).thenAnswer((_) async {});
      when(() => cast.previous()).thenAnswer((_) async {});
      when(() => cast.seek(any())).thenAnswer((_) async {});
      when(() => cast.setVolume(any())).thenAnswer((_) async {});
      when(() => cast.replaceQueue(any())).thenAnswer((_) async {});
      when(() => cast.playTrack(any(), any())).thenAnswer((_) async {});
      when(() => cast.playIndex(any())).thenAnswer((_) async {});
      when(() => cast.addToQueue(any())).thenAnswer((_) async {});
      when(() => cast.addNextToQueue(any())).thenAnswer((_) async {});
      when(() => cast.removeAt(any())).thenAnswer((_) async {});
      when(() => cast.removeTrack(any())).thenAnswer((_) async {});
      when(() => cast.reorder(any(), any())).thenAnswer((_) async {});
      when(() => cast.playHistoryTrack(any())).thenAnswer((_) async {});
      when(() => cast.toggleShuffle()).thenAnswer((_) async {});
      when(() => cast.disconnect(resumeLocal: any(named: 'resumeLocal')))
          .thenAnswer((_) async {});
      final owner = ActivePlayback(local: harness.service, cast: cast);
      addTearDown(owner.dispose);
      final localCalls = harness.player.calls.length;

      await owner.toggle();
      verify(() => cast.toggle()).called(1);
      await owner.play();
      await owner.pause();
      await owner.next();
      await owner.previous();
      await owner.seek(const Duration(seconds: 3));
      verify(() => cast.seek(const Duration(seconds: 3))).called(1);
      await owner.setVolumeSlider(0.5);
      verify(() => cast.setVolume(0.5)).called(1);
      await owner.replaceQueue([_track('n')]);
      verify(() => cast.replaceQueue([_track('n')])).called(1);
      await owner.playQueueIndex(1);
      verify(() => cast.playIndex(1)).called(1);
      await owner.playUpcomingIndex(1);
      verify(() => cast.playIndex(2)).called(1);
      await owner.addToQueue(_track('n'));
      verify(() => cast.addToQueue(_track('n'))).called(1);
      await owner.addNextToQueue([_track('n')]);
      await owner.removeAt(0);
      await owner.removeTrack('remote-0');
      await owner.reorder(0, 1);
      verify(() => cast.reorder(0, 1)).called(1);
      // Reordering onto the pinned current entry is rejected.
      await expectLater(
        owner.reorderUpcoming(1, 2),
        throwsA(isA<PlaybackActionUnavailable>()),
      );
      when(() => cast.remoteIndex).thenReturn(0);
      await owner.reorderUpcoming(1, 2);
      verify(() => cast.reorder(1, 2)).called(1);
      when(() => cast.remoteIndex).thenReturn(1);
      await owner.removeUpcomingAt(1);
      verify(() => cast.removeAt(2)).called(1);
      await owner.playHistoryTrack(_track('n'));
      await owner.toggleShuffle();
      verify(() => cast.toggleShuffle()).called(1);

      expect(harness.player.calls.length, localCalls);
    });

    test('cast repeat is disabled with a typed error', () async {
      final harness = PlaybackHarness();
      addTearDown(harness.dispose);
      await harness.configure();

      final cast = _MockCast();
      _stubCastRemote(cast);
      final owner = ActivePlayback(local: harness.service, cast: cast);
      addTearDown(owner.dispose);

      await expectLater(
        owner.cycleRepeat(),
        throwsA(isA<PlaybackActionUnavailable>()),
      );
      expect(owner.state.error, contains('Repeat'));
    });

    test('invalid upcoming indices are rejected on Cast', () async {
      final harness = PlaybackHarness();
      addTearDown(harness.dispose);
      await harness.configure();

      final cast = _MockCast();
      _stubCastRemote(cast);
      final owner = ActivePlayback(local: harness.service, cast: cast);
      addTearDown(owner.dispose);

      await expectLater(
        owner.playUpcomingIndex(99),
        throwsA(isA<PlaybackActionUnavailable>()),
      );
      await expectLater(
        owner.reorderUpcoming(0, 1),
        throwsA(isA<PlaybackActionUnavailable>()),
      );
      verifyNever(() => cast.playIndex(any()));
    });

    test('frozen handoff rejects ordinary actions', () async {
      final harness = PlaybackHarness();
      addTearDown(harness.dispose);
      await harness.configure();

      final cast = _MockCast();
      _stubCastIdle(cast);
      when(() => cast.ownership).thenReturn(CastOwnership.transferring);
      final owner = ActivePlayback(local: harness.service, cast: cast);
      addTearDown(owner.dispose);

      expect(owner.state.capabilities, isEmpty);
      await expectLater(
        owner.next(),
        throwsA(isA<PlaybackActionUnavailable>()),
      );
      await expectLater(
        owner.resumeHere(),
        throwsA(isA<PlaybackActionUnavailable>()),
      );
    });

    test('resumeHere delegates to Cast disconnect', () async {
      final harness = PlaybackHarness();
      addTearDown(harness.dispose);
      await harness.configure();

      final cast = _MockCast();
      _stubCastRemote(cast);
      when(() => cast.disconnect(resumeLocal: any(named: 'resumeLocal')))
          .thenAnswer((_) async {});
      final owner = ActivePlayback(local: harness.service, cast: cast);
      addTearDown(owner.dispose);

      await owner.resumeHere();
      verify(() => cast.disconnect(resumeLocal: true)).called(1);
    });

    test('adapter errors are recorded redacted', () async {
      final harness = PlaybackHarness();
      addTearDown(harness.dispose);
      await harness.configure();

      final cast = _MockCast();
      _stubCastRemote(cast);
      when(() => cast.next())
          .thenThrow(const CastException('token=abc123 should not leak'));
      final owner = ActivePlayback(local: harness.service, cast: cast);
      addTearDown(owner.dispose);

      await expectLater(owner.next(), throwsA(isA<CastException>()));
      expect(owner.state.error, isNot(contains('abc123')));
    });
  });

  group('provider', () {
    test('builds without discovery and disposes once', () async {
      final harness = PlaybackHarness();
      addTearDown(harness.dispose);
      await harness.configure();

      final cast = _MockCast();
      _stubCastIdle(cast);
      final container = ProviderContainer(
        overrides: [
          playbackProvider.overrideWithValue(harness.service),
          castControllerProvider.overrideWithValue(cast),
        ],
      );

      final owner = container.read(activePlaybackProvider);
      expect(owner.state.destination, PlaybackDestination.local);
      verifyNever(() => cast.dispose());

      container.dispose();
      verify(() => cast.removeListener(any())).called(greaterThanOrEqualTo(1));
      // Borrowed adapters stay alive for their own providers.
      verifyNever(() => cast.dispose());
      expect(harness.service.queue, isNotNull);
      expect(harness.player.isDisposed, isFalse);
      owner.dispose();
    });
  });
}

void _stubCastIdle(_MockCast cast) {
  when(() => cast.ownership).thenReturn(CastOwnership.local);
  when(() => cast.castQueue).thenReturn(const []);
  when(() => cast.remoteIndex).thenReturn(0);
  when(() => cast.remoteTrack).thenReturn(null);
  when(() => cast.remoteEntryId).thenReturn(null);
  when(() => cast.castHistory).thenReturn(const []);
  when(() => cast.remotePlaying).thenReturn(false);
  when(() => cast.remotePosition).thenReturn(Duration.zero);
  when(() => cast.remoteDuration).thenReturn(null);
  when(() => cast.remoteVolume).thenReturn(1.0);
  when(() => cast.castShuffle).thenReturn(false);
  when(() => cast.castRepeatMode).thenReturn(LoopMode.off);
  when(() => cast.positionStream).thenAnswer((_) => Stream<Duration>.empty());
  when(() => cast.addListener(any())).thenReturn(null);
  when(() => cast.removeListener(any())).thenReturn(null);
}

void _stubCastRemote(_MockCast cast) {
  final queue = [_track('remote-0'), _track('remote-1'), _track('remote-2')];
  when(() => cast.ownership).thenReturn(CastOwnership.remote);
  when(() => cast.castQueue).thenReturn(queue);
  when(() => cast.remoteIndex).thenReturn(1);
  when(() => cast.remoteTrack).thenReturn(queue[1]);
  when(() => cast.remoteEntryId).thenReturn('remote-entry-1');
  when(() => cast.castHistory).thenReturn(const []);
  when(() => cast.remotePlaying).thenReturn(true);
  when(() => cast.remotePosition).thenReturn(const Duration(seconds: 12));
  when(() => cast.remoteDuration).thenReturn(const Duration(minutes: 3));
  when(() => cast.remoteVolume).thenReturn(0.3);
  when(() => cast.castShuffle).thenReturn(true);
  when(() => cast.castRepeatMode).thenReturn(LoopMode.off);
  when(() => cast.positionStream).thenAnswer((_) => Stream<Duration>.empty());
  when(() => cast.addListener(any())).thenReturn(null);
  when(() => cast.removeListener(any())).thenReturn(null);
}
