import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show IndexedAudioSource;

import 'support/playback_harness.dart';

void main() {
  test('manual edit then shuffle preserves current entry', () async {
    final harness = PlaybackHarness();
    addTearDown(harness.dispose);
    await harness.configure();

    final catalog = playbackCatalog(250);
    await harness.service.replaceQueue(catalog, startIndex: 120);
    await harness.settle();
    expect(harness.service.currentTrack?.id, 'track-120');
    final currentId = _playingEntryId(harness, 'track-120');

    final extra = playbackTrack(999);
    await harness.service.addToQueue(extra);
    await harness.settle();
    expect(harness.service.queue, hasLength(101));
    expect(harness.service.currentTrack?.id, 'track-120');

    await harness.service.toggleShuffle();
    await harness.settle();

    expect(harness.service.currentTrack?.id, 'track-120');
    expect(_playingEntryId(harness, 'track-120'), currentId);
    expect(
      harness.service.queue.map((track) => track.id),
      contains('track-999'),
    );
    // Loaded prefix through current is intact; nothing was lost.
    expect(harness.service.queue.length, 101);
  });

  test('failed audio edit preserves visible queue and saved state', () async {
    final harness = PlaybackHarness();
    addTearDown(harness.dispose);
    await harness.configure();

    await harness.service.replaceQueue(playbackCatalog(3), startIndex: 0);
    await harness.settle();
    final savedBefore = harness.stateStore.values[PlaybackHarness.accountId];
    expect(savedBefore, isNotNull);

    harness.player.audioError = Exception('remove failed');
    await expectLater(harness.service.removeAt(1), throwsException);
    await harness.settle();

    expect(harness.service.queue.map((track) => track.id), [
      'track-0',
      'track-1',
      'track-2',
    ]);
    expect(harness.service.currentTrack?.id, 'track-0');
    // Recovery reloaded the prior audio snapshot.
    expect(harness.player.sources, hasLength(3));
    expect(harness.stateStore.values[PlaybackHarness.accountId], savedBefore);
    expect(harness.service.history, isEmpty);

    // The chain survives: an operation after a prior failure still runs.
    harness.player.audioError = null;
    await harness.service.removeAt(1);
    await harness.settle();
    expect(harness.service.queue.map((track) => track.id), [
      'track-0',
      'track-2',
    ]);
  });

  test(
    'failed source replacement preserves state and stops on lost recovery',
    () async {
      final harness = PlaybackHarness();
      addTearDown(harness.dispose);
      await harness.configure();

      await harness.service.replaceQueue(playbackCatalog(5), startIndex: 0);
      await harness.settle();
      final stopsBefore = harness.player.stopCalls;

      harness.player.loadError = Exception('load failed');
      await expectLater(
        harness.service.replaceQueue(playbackCatalog(5), startIndex: 2),
        throwsException,
      );
      await harness.settle();

      // Prior logical queue retained; recovery failure stopped audio without
      // publishing the candidate.
      expect(harness.service.queue.map((track) => track.id), [
        'track-0',
        'track-1',
        'track-2',
        'track-3',
        'track-4',
      ]);
      expect(harness.service.currentTrack?.id, 'track-0');
      expect(harness.player.stopCalls, greaterThan(stopsBefore));

      harness.player.loadError = null;
      await harness.service.replaceQueue(playbackCatalog(5), startIndex: 2);
      await harness.settle();
      expect(harness.service.currentTrack?.id, 'track-2');
    },
  );

  test('extension then replacement keeps the replacement', () async {
    final harness = PlaybackHarness();
    addTearDown(harness.dispose);
    await harness.configure();

    await harness.service.replaceQueue(playbackCatalog(250), startIndex: 120);
    await harness.settle();
    expect(harness.service.queue, hasLength(100));

    // Occupy the chain so extension and replacement order deterministically.
    harness.player.seekGate = Completer<void>();
    final seek = harness.service.seek(const Duration(seconds: 1));
    final extension = harness.service.playQueueIndex(90);
    final replacement = harness.service.replaceQueue(
      playbackCatalog(10),
      startIndex: 0,
    );
    await harness.settle();
    harness.player.seekGate?.complete();
    await seek;
    await extension;
    await replacement;
    await harness.settle();

    expect(harness.service.queue.map((track) => track.id), [
      for (var i = 0; i < 10; i++) 'track-$i',
    ]);
    expect(harness.service.currentTrack?.id, 'track-0');
  });

  test('clear during load leaves no queue and no saved state', () async {
    final harness = PlaybackHarness();
    addTearDown(harness.dispose);
    await harness.configure();

    harness.player.loadGate = Completer<void>();
    final load = harness.service.replaceQueue(
      playbackCatalog(50),
      startIndex: 10,
    );
    await harness.settle();
    final clearing = harness.service.clear();
    await harness.settle();
    harness.player.loadGate?.complete();
    await clearing;
    await load;
    await harness.settle();

    expect(harness.service.queue, isEmpty);
    expect(
      harness.stateStore.values.containsKey(PlaybackHarness.accountId),
      isFalse,
    );
  });

  test('delayed old events after replacement and clear are ignored', () async {
    final harness = PlaybackHarness();
    addTearDown(harness.dispose);
    await harness.configure();

    await harness.service.replaceQueue(playbackCatalog(5), startIndex: 0);
    await harness.settle();

    // Hold the replacement install so an old index event lands after commit.
    harness.player.loadGate = Completer<void>();
    final replacement = harness.service.replaceQueue(
      playbackCatalog(3),
      startIndex: 0,
    );
    await harness.settle();
    harness.player.emitIndex(4);
    harness.player.loadGate?.complete();
    await replacement;
    await harness.settle();

    expect(harness.service.queue.map((track) => track.id), [
      'track-0',
      'track-1',
      'track-2',
    ]);
    expect(harness.service.history, isEmpty);
    expect(harness.service.currentTrack?.id, 'track-0');

    await harness.service.clear();
    await harness.settle();
    harness.player.emitIndex(0);
    await harness.settle();
    expect(harness.service.queue, isEmpty);
    expect(harness.service.history, isEmpty);
  });

  test('repeated next and previous stay consistent', () async {
    final harness = PlaybackHarness();
    addTearDown(harness.dispose);
    await harness.configure();

    await harness.service.replaceQueue(playbackCatalog(5), startIndex: 0);
    await harness.settle();

    await harness.service.next();
    harness.player.emitIndex(1);
    await harness.service.next();
    harness.player.emitIndex(2);
    await harness.settle();
    expect(harness.service.currentTrack?.id, 'track-2');
    expect(harness.service.history.map((track) => track.id), [
      'track-1',
      'track-0',
    ]);

    await harness.service.previous();
    await harness.settle();
    expect(harness.service.currentTrack?.id, 'track-1');
    expect(harness.service.history.map((track) => track.id), ['track-0']);
  });

  test('duplicate occurrences record one history entry each', () async {
    final harness = PlaybackHarness();
    addTearDown(harness.dispose);
    await harness.configure();

    final first = playbackTrack(0);
    final second = playbackTrack(1);
    await harness.service.replaceQueue([first, second, first], startIndex: 0);
    await harness.settle();

    await harness.service.next();
    harness.player.emitIndex(1);
    await harness.settle();
    expect(harness.service.history.map((track) => track.id), ['track-0']);

    await harness.service.playQueueIndex(2);
    await harness.settle();
    expect(harness.service.history.map((track) => track.id), [
      'track-1',
      'track-0',
    ]);
    expect(harness.service.currentTrack?.id, 'track-0');

    final playing = harness.reportsFor('/Sessions/Playing');
    expect(playing, isNotEmpty);
    final entryIds = playing
        .expand(
          (report) => ((report.body['NowPlayingQueue'] as List?) ?? const [])
              .cast<Map<String, dynamic>>(),
        )
        .map((entry) => entry['PlaylistItemId'] as String?)
        .whereType<String>()
        .toSet();
    // Every reported occurrence id is distinct even for duplicate tracks.
    expect(entryIds.length, greaterThanOrEqualTo(3));
  });

  test('report ownership during Cast handoff keeps only the stop', () async {
    final harness = PlaybackHarness();
    addTearDown(harness.dispose);
    await harness.configure();

    await harness.service.replaceQueue(playbackCatalog(5), startIndex: 0);
    await harness.waitForReports(1);
    await harness.settle();

    harness.reports.clear();
    harness.service.setCastingActive(true);

    await harness.service.next();
    await harness.settle();

    final playing = harness.reportsFor('/Sessions/Playing');
    final stopped = harness.reportsFor('/Sessions/Playing/Stopped');
    expect(playing, isEmpty);
    expect(stopped, hasLength(1));
    // Local queue still advanced for later resume.
    expect(harness.service.currentTrack?.id, 'track-1');
  });

  test('shuffle enable then disable preserves order', () async {
    final harness = PlaybackHarness();
    addTearDown(harness.dispose);
    await harness.configure();

    await harness.service.replaceQueue(playbackCatalog(10), startIndex: 0);
    await harness.settle();

    await harness.service.toggleShuffle();
    await harness.settle();
    expect(harness.service.shuffle, isTrue);
    expect(harness.service.currentTrack?.id, 'track-0');

    await harness.service.toggleShuffle();
    await harness.settle();
    expect(harness.service.shuffle, isFalse);
    expect(harness.service.currentTrack?.id, 'track-0');
  });

  test(
    'toggling shuffle keeps the playing source and position intact',
    () async {
      final harness = PlaybackHarness();
      addTearDown(harness.dispose);
      await harness.configure();

      await harness.service.replaceQueue(playbackCatalog(250), startIndex: 80);
      await harness.settle();
      harness.player.emitPosition(const Duration(seconds: 42));
      final activeSource = harness.player.sources[20];
      final originalOrder = harness.service.queue
          .map((track) => track.id)
          .toList();
      final setSourcesCalls = harness.player.calls
          .where((call) => call == 'setAudioSources')
          .length;
      final stopCalls = harness.player.stopCalls;
      final playCalls = harness.player.playCalls;

      await harness.service.toggleShuffle();
      await harness.settle();

      expect(harness.service.shuffle, isTrue);
      expect(harness.service.currentTrack?.id, 'track-80');
      expect(harness.player.currentIndex, 20);
      expect(harness.player.sources, hasLength(100));
      expect(
        harness.service.queue.map((track) => track.id),
        isNot(equals(originalOrder)),
      );
      expect(
        harness.player.sources.map(
          (source) => (source as IndexedAudioSource).tag.id as String,
        ),
        harness.service.queue.map((track) => track.id),
      );
      expect(harness.player.position, const Duration(seconds: 42));
      expect(identical(harness.player.sources[20], activeSource), isTrue);
      expect(
        harness.player.calls.where((call) => call == 'setAudioSources').length,
        setSourcesCalls,
      );
      expect(harness.player.stopCalls, stopCalls);
      expect(harness.player.playCalls, playCalls);

      final shuffledUpcoming = harness.service.queue
          .skip(21)
          .map((track) => track.id)
          .toList();
      await harness.service.toggleShuffle();
      await harness.settle();

      expect(harness.service.shuffle, isFalse);
      expect(
        harness.service.queue.skip(21).map((track) => track.id),
        shuffledUpcoming,
      );
      expect(harness.service.currentTrack?.id, 'track-80');
      expect(harness.player.position, const Duration(seconds: 42));
      expect(harness.player.stopCalls, stopCalls);
      expect(harness.player.playCalls, playCalls);

      final nextTrack = harness.service.queue[21].id;
      harness.player.emitIndex(21);
      await harness.settle();
      expect(harness.service.currentTrack?.id, nextTrack);
      expect(harness.service.history.first.id, 'track-80');
    },
  );

  test('queue persistence round-trips through restore', () async {
    final harness = PlaybackHarness();
    addTearDown(harness.dispose);
    await harness.configure();

    await harness.service.replaceQueue(playbackCatalog(250), startIndex: 120);
    await harness.service.next();
    await harness.settle();

    final saved = harness.stateStore.values[PlaybackHarness.accountId];
    expect(saved, isNotNull);
    final decoded = jsonDecode(saved!) as Map<String, dynamic>;
    expect((decoded['queue'] as List), hasLength(100));
    expect(decoded['index'], 21);
  });
}

/// Occurrence id currently reported as playing for [trackId], if any.
String? _playingEntryId(PlaybackHarness harness, String trackId) {
  final playing = harness.reportsFor('/Sessions/Playing');
  for (final report in playing.reversed) {
    if (report.body['ItemId'] == trackId) {
      return report.body['PlaylistItemId'] as String?;
    }
  }
  return null;
}
