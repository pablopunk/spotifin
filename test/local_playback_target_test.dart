import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotifin/services/playback/local_playback_target.dart';
import 'package:spotifin/services/playback/remote_command_handler.dart';
import 'package:spotifin/storage/database.dart';

import 'support/playback_harness.dart';

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
  test('explicit local commands stop Cast before acting', () async {
    final harness = PlaybackHarness();
    addTearDown(harness.dispose);
    await harness.configure();
    await harness.service.replaceQueue(playbackCatalog(3), startIndex: 0);
    await harness.settle();

    final transfers = <String>[];
    final target = LocalPlaybackTarget(harness.service, () async {
      transfers.add('transfer');
      harness.service.setCastingActive(false);
    });
    harness.service.setCastingActive(true);

    await target.pause();
    await harness.settle();

    expect(transfers, ['transfer']);
    expect(harness.service.playing, isFalse);
  });

  test('failed Cast stop prevents the local action', () async {
    final harness = PlaybackHarness();
    addTearDown(harness.dispose);
    await harness.configure();
    await harness.service.replaceQueue(playbackCatalog(3), startIndex: 0);
    await harness.settle();
    final playsBefore = harness.player.playCalls;

    final target = LocalPlaybackTarget(harness.service, () async {
      throw Exception('receiver stuck');
    });

    await expectLater(target.play(), throwsException);
    await harness.settle();
    expect(harness.player.playCalls, playsBefore);
  });

  test('takeover transfers first, then replaces locally', () async {
    final harness = PlaybackHarness();
    addTearDown(harness.dispose);
    await harness.configure();
    await harness.service.replaceQueue(playbackCatalog(2), startIndex: 0);
    await harness.settle();

    final order = <String>[];
    final target = LocalPlaybackTarget(harness.service, () async {
      order.add('transfer');
    });

    final tracks = [_track('n-0'), _track('n-1')];
    await target.takeOver(tracks, startIndex: 1, position: Duration.zero);
    await harness.settle();

    expect(order, ['transfer']);
    expect(harness.service.queue.map((track) => track.id), ['n-0', 'n-1']);
    expect(harness.service.currentTrack?.id, 'n-1');
  });

  test('invalid remote handoff leaves transfer and source alone', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.upsertTracks([
      TracksCompanion.insert(id: 'kept', name: 'Kept'),
    ]);

    final harness = PlaybackHarness();
    addTearDown(harness.dispose);
    await harness.configure();
    await harness.service.replaceQueue(playbackCatalog(2), startIndex: 0);
    await harness.settle();

    var transfers = 0;
    final target = LocalPlaybackTarget(harness.service, () async {
      transfers++;
    });
    final handler = RemoteCommandHandler(target, database);

    // Unknown ids fail handler validation before any target call.
    await handler.handle('Play', {
      'PlayCommand': 'PlayNow',
      'ItemIds': ['missing'],
      'StartIndex': 0,
    });
    await harness.settle();

    expect(transfers, 0);
    expect(harness.service.queue.map((track) => track.id), [
      'track-0',
      'track-1',
    ]);

    // A valid command transfers first, then takes over locally.
    await database.upsertTracks([
      TracksCompanion.insert(id: 'track-0', name: 'Zero'),
      TracksCompanion.insert(id: 'track-1', name: 'One'),
    ]);
    await handler.handle('Play', {
      'PlayCommand': 'PlayNow',
      'ItemIds': ['track-0', 'track-1'],
      'StartIndex': 1,
    });
    await harness.settle();

    expect(transfers, 1);
    expect(harness.service.currentTrack?.id, 'track-1');
  });
}
