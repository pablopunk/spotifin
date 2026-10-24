import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

import 'support/playback_harness.dart';

void main() {
  test('local audio starts before the queue save completes', () async {
    final local = Uri.file('/downloads/song.mp3');
    final harness = PlaybackHarness(localFiles: {'track-0': local});
    addTearDown(harness.dispose);
    await harness.configure();
    final gate = Completer<void>();
    harness.stateStore.writeGate = gate;
    final replacement = harness.service.replaceQueue(playbackCatalog(2));
    try {
      await harness.settle();
      expect(harness.stateStore.writes, isEmpty);
      expect(harness.player.playing, isTrue);
      expect((harness.player.sources.first as UriAudioSource).uri, local);
      expect((harness.player.sources[1] as UriAudioSource).uri.scheme, 'https');
      await harness.waitForReports(1);
      expect(
        harness.reportsFor('/Sessions/Playing').single.body['IsPaused'],
        isFalse,
      );
    } finally {
      gate.complete();
      await replacement;
    }
    expect(harness.stateStore.writes, isNotEmpty);
  });

  test(
    'stalled Jellyfin reports do not block local playback or next',
    () async {
      final stalled = Completer<http.Response>();
      final local = Uri.file('/downloads/song.mp3');
      final harness = PlaybackHarness(
        localFiles: {'track-0': local, 'track-1': local},
        reportResponse: (_) => stalled.future,
      );
      addTearDown(harness.dispose);
      await harness.configure();
      try {
        await harness.service.replaceQueue(playbackCatalog(2));
        await harness.waitForReports(1);
        expect(stalled.isCompleted, isFalse);
        expect(harness.player.playing, isTrue);
        expect((harness.player.sources.first as UriAudioSource).uri, local);
        await harness.service.next();
        expect(harness.service.currentTrack?.id, 'track-1');
        expect(harness.player.playing, isTrue);
      } finally {
        stalled.complete(http.Response('', 204));
      }
      await harness.settle();
      expect(harness.reportsFor('/Sessions/Playing/Stopped'), isNotEmpty);
      expect(
        harness.reportsFor('/Sessions/Playing').last.body['ItemId'],
        'track-1',
      );
    },
  );

  test('a timed out report releases the reporting lane', () async {
    final stalled = Completer<http.Response>();
    var requests = 0;
    final harness = PlaybackHarness(
      requestTimeout: const Duration(milliseconds: 20),
      reportResponse: (_) {
        requests++;
        return requests == 1
            ? stalled.future
            : Future.value(http.Response('', 204));
      },
    );
    addTearDown(harness.dispose);
    await harness.configure();
    try {
      await harness.service.replaceQueue(playbackCatalog(2));
      await harness.service.next();
      await harness.waitForReports(3);
      expect(harness.player.playing, isTrue);
      expect(stalled.isCompleted, isFalse);
      expect(
        harness.reportsFor('/Sessions/Playing').last.body['ItemId'],
        'track-1',
      );
      expect(requests, greaterThan(1));
    } finally {
      stalled.complete(http.Response('', 204));
    }
  });

  test('constructs and disposes without native audio', () async {
    final harness = PlaybackHarness();
    await harness.configure();
    expect(harness.service.queue, isEmpty);
    expect(harness.player.isDisposed, isFalse);
    expect(harness.player.calls, isEmpty);

    harness.service.dispose();
    await harness.settle();
    expect(harness.player.isDisposed, isTrue);
    expect(harness.player.disposeCalls, 1);
    harness.client.close();
  });

  test('replaceQueue loads a window and preserves a selected track', () async {
    final harness = PlaybackHarness();
    addTearDown(harness.dispose);
    await harness.configure();

    final catalog = playbackCatalog(250);
    const start = 125;
    await harness.service.replaceQueue(catalog, startIndex: start);
    await harness.waitForReports(1);
    await harness.settle();

    // Initial window: 100 tracks with up to 20 tracks behind the start.
    expect(harness.service.queue, hasLength(100));
    expect(harness.service.currentIndex, 20);
    expect(harness.service.queue[20].id, 'track-125');
    expect(harness.service.currentTrack?.id, 'track-125');
    expect(harness.player.sources, hasLength(100));
    expect(harness.player.lastSetInitialIndex, 20);
  });

  test('duplicate tracks receive distinct playlist entry ids', () async {
    final harness = PlaybackHarness();
    addTearDown(harness.dispose);
    await harness.configure();

    final first = playbackTrack(0);
    final second = playbackTrack(1);
    await harness.service.replaceQueue([first, second, first], startIndex: 0);
    await harness.waitForReports(1);
    await harness.settle();

    final playing = harness.reports
        .where((report) => report.endpoint == '/Sessions/Playing')
        .toList();
    expect(playing, isNotEmpty);
    final queue = (playing.first.body['NowPlayingQueue'] as List)
        .cast<Map<String, dynamic>>();
    expect(queue.map((entry) => entry['Id']), [
      'track-0',
      'track-1',
      'track-0',
    ]);
    final entryIds = queue.map((entry) => entry['PlaylistItemId']).toList();
    expect(entryIds.toSet(), hasLength(3));
  });

  test('restore loads saved queue without autoplay', () async {
    final harness = PlaybackHarness();
    addTearDown(harness.dispose);
    await harness.configure();

    final catalog = playbackCatalog(10);
    const ids = ['track-2', 'track-5', 'track-7'];
    harness.stateStore.seed(
      PlaybackHarness.accountId,
      jsonEncode({
        'queue': ids,
        'index': 1,
        'positionMilliseconds': 45000,
        'shuffle': false,
      }),
    );

    await harness.service.restore(catalog);
    await harness.settle();

    expect(harness.service.queue.map((track) => track.id), ids);
    expect(harness.service.currentIndex, 1);
    expect(harness.service.currentTrack?.id, 'track-5');
    expect(harness.player.sources, hasLength(3));
    expect(harness.player.lastSetInitialIndex, 1);
    expect(harness.player.lastSetInitialPosition, const Duration(seconds: 45));
    expect(harness.player.playCalls, 0);
    expect(harness.player.pauseCalls, greaterThanOrEqualTo(1));
  });

  test('restore keeps a queue started before it ran', () async {
    final harness = PlaybackHarness();
    addTearDown(harness.dispose);
    await harness.configure();

    final catalog = playbackCatalog(10);
    harness.stateStore.seed(
      PlaybackHarness.accountId,
      jsonEncode({
        'queue': ['track-2', 'track-5'],
        'index': 0,
        'positionMilliseconds': 0,
        'shuffle': false,
      }),
    );

    final shuffled = harness.service.replaceQueue(catalog, shuffle: true);
    final restored = harness.service.restore(catalog);
    await Future.wait([shuffled, restored]);
    await harness.settle();

    expect(harness.service.queue, hasLength(catalog.length));
    expect(harness.service.shuffle, isTrue);
    expect(harness.player.playing, isTrue);
    expect(harness.player.pauseCalls, 0);
    expect(harness.stateStore.reads, isEmpty);
  });

  test('restore loads the saved queue again after clear', () async {
    final harness = PlaybackHarness();
    addTearDown(harness.dispose);
    await harness.configure();

    final catalog = playbackCatalog(10);
    await harness.service.replaceQueue(catalog);
    await harness.service.clear();
    await harness.configure();
    harness.stateStore.seed(
      PlaybackHarness.accountId,
      jsonEncode({
        'queue': ['track-2', 'track-5'],
        'index': 0,
        'positionMilliseconds': 0,
        'shuffle': false,
      }),
    );

    await harness.service.restore(catalog);
    await harness.settle();

    expect(harness.service.queue.map((track) => track.id), [
      'track-2',
      'track-5',
    ]);
  });

  test('manual next records the outgoing track once', () async {
    final harness = PlaybackHarness();
    addTearDown(harness.dispose);
    await harness.configure();

    final catalog = playbackCatalog(5);
    await harness.service.replaceQueue(catalog, startIndex: 0);
    await harness.waitForReports(1);
    await harness.settle();
    expect(harness.service.history, isEmpty);

    await harness.service.next();
    harness.player.emitIndex(1);
    await harness.settle();

    expect(harness.service.history, hasLength(1));
    expect(harness.service.history.single.id, 'track-0');
  });

  test('Cast ownership suppresses local progress reports', () async {
    final harness = PlaybackHarness();
    addTearDown(harness.dispose);
    await harness.configure();

    final catalog = playbackCatalog(5);
    await harness.service.replaceQueue(catalog, startIndex: 0);
    await harness.waitForReports(1);
    await harness.settle();

    harness.reports.clear();
    harness.service.setCastingActive(true);

    await harness.service.seek(const Duration(seconds: 5));
    await harness.settle();

    final progress = harness.reports
        .where((report) => report.endpoint == '/Sessions/Playing/Progress')
        .toList();
    expect(progress, isEmpty);
    expect(harness.service.queue, isNotEmpty);
  });

  test('paused snapshot restore never starts audio', () async {
    final harness = PlaybackHarness();
    addTearDown(harness.dispose);
    await harness.configure();

    await harness.service.replaceQueue(playbackCatalog(5), startIndex: 2);
    await harness.settle();
    await harness.service.pause();
    await harness.settle();
    final playsBefore = harness.player.playCalls;

    final snapshot = harness.service.captureSnapshot();
    expect(snapshot.playing, isFalse);
    expect(snapshot.position, harness.player.position);

    await harness.service.next();
    await harness.settle();
    expect(harness.service.currentTrack?.id, 'track-3');

    await harness.service.restoreSnapshot(snapshot);
    await harness.settle();

    expect(harness.service.currentTrack?.id, 'track-2');
    expect(harness.service.currentIndex, 2);
    expect(harness.player.playCalls, playsBefore);
    expect(harness.service.playing, isFalse);
  });

  test('snapshot restore retains duplicate occurrence identity', () async {
    final harness = PlaybackHarness();
    addTearDown(harness.dispose);
    await harness.configure();

    final first = playbackTrack(0);
    final second = playbackTrack(1);
    await harness.service.replaceQueue([first, second, first], startIndex: 0);
    await harness.waitForReports(1);
    await harness.settle();

    Set<String?> entryIds() => harness
        .reportsFor('/Sessions/Playing')
        .expand(
          (report) => ((report.body['NowPlayingQueue'] as List?) ?? const [])
              .cast<Map<String, dynamic>>(),
        )
        .map((entry) => entry['PlaylistItemId'] as String?)
        .whereType<String>()
        .toSet();

    final before = entryIds();
    expect(before, hasLength(3));

    final snapshot = harness.service.captureSnapshot();
    await harness.service.next();
    await harness.settle();
    await harness.service.restoreSnapshot(snapshot);
    await harness.settle();

    expect(harness.service.currentTrack?.id, 'track-0');
    expect(harness.service.currentIndex, 0);
    final after = entryIds();
    expect(after, before);
  });

  test('dispose stops listening to player events', () async {
    final harness = PlaybackHarness();
    await harness.configure();

    final catalog = playbackCatalog(3);
    await harness.service.replaceQueue(catalog, startIndex: 0);
    await harness.waitForReports(1);
    await harness.settle();
    final count = harness.reports.length;

    harness.service.dispose();
    await harness.settle();
    expect(harness.player.isDisposed, isTrue);

    harness.player.emitIndex(1);
    harness.player.emitPosition(const Duration(seconds: 3));
    harness.player.emitCompletion();
    harness.player.emitShuffle(true);
    await harness.settle();

    expect(harness.reports.length, count);
    harness.client.close();
  });
}
