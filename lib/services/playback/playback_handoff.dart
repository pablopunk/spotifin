import '../../storage/database.dart';
import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/remote_session.dart';
import '../jellyfin/session.dart';
import 'remote_playback.dart';

class PlaybackHandoff {
  const PlaybackHandoff(this._client, this._playback, this._database);

  final JellyfinClient _client;
  final RemotePlayback _playback;
  final AppDatabase _database;

  Future<List<RemoteSession>> takeOver(
    JellyfinSession session,
    RemoteSession source,
  ) async {
    if (source.nowPlayingItemId == null) return _client.fetchSessions(session);
    final allTracks = await _database.allTracks();
    final tracksById = {for (final track in allTracks) track.id: track};
    final sourceQueue = source.queue.isEmpty
        ? [RemoteQueueItem(itemId: source.nowPlayingItemId!)]
        : source.queue;
    final sourceIndex = _sourceIndex(source, sourceQueue);
    if (sourceIndex < 0 ||
        tracksById[sourceQueue[sourceIndex].itemId] == null) {
      throw const JellyfinException(
        'The current song is not available on this device.',
      );
    }
    final localTracks = <Track>[];
    var localIndex = 0;
    for (var index = 0; index < sourceQueue.length; index++) {
      final track = tracksById[sourceQueue[index].itemId];
      if (track == null) continue;
      if (index < sourceIndex) localIndex++;
      localTracks.add(track);
    }
    await _playback.takeOver(
      localTracks,
      startIndex: localIndex,
      position: source.position,
    );
    final latest = await _client.fetchSessions(session);
    final unchanged = latest.any(
      (item) =>
          item.id == source.id &&
          item.nowPlayingItemId == source.nowPlayingItemId &&
          (source.playlistItemId == null ||
              item.playlistItemId == source.playlistItemId),
    );
    if (unchanged) {
      await _client.sendPlaystateCommand(session, source.id, 'Stop');
    }
    return latest;
  }

  int _sourceIndex(RemoteSession source, List<RemoteQueueItem> queue) {
    if (source.playlistItemId != null) {
      final exact = queue.indexWhere(
        (item) => item.playlistItemId == source.playlistItemId,
      );
      if (exact >= 0) return exact;
    }
    return queue.indexWhere((item) => item.itemId == source.nowPlayingItemId);
  }
}
