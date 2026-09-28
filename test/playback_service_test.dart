import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'support/playback_harness.dart';

void main() {
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
