import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../platform/playback_state_store.dart';
import '../../storage/database.dart';
import '../downloads/download_service.dart';
import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/session.dart';
import 'collection_queue.dart';
import 'mobile_queue.dart';
import 'playback_history.dart';
import 'queue_item_identity.dart';
import 'remote_playback.dart';

class PlaybackService extends ChangeNotifier implements RemotePlayback {
  PlaybackService(this._client, this._downloads) {
    _subscriptions.add(
      _player.playerStateStream.listen((playerState) {
        if (playerState.processingState == ProcessingState.completed) {
          unawaited(_finishCompletedQueue());
        } else {
          unawaited(_reportProgress());
        }
        notifyListeners();
      }),
    );
    _subscriptions.add(
      _player.currentIndexStream.listen((_) {
        if (_loadingSources) return;
        _handleTrackChange();
        _saveQueue();
        notifyListeners();
      }),
    );
    _subscriptions.add(
      _player.positionStream.listen((position) {
        final second = position.inSeconds;
        if (second != _lastSavedSecond) {
          _lastSavedSecond = second;
          _savePosition(position);
        }
        if (second % 10 == 0) {
          _reportProgress();
        }
      }),
    );
    _subscriptions.add(
      _player.shuffleModeEnabledStream.listen((enabled) {
        if (enabled) unawaited(_player.setShuffleModeEnabled(false));
      }),
    );
  }

  final JellyfinClient _client;
  final DownloadService _downloads;
  final PlaybackStateStore _stateStore = PlaybackStateStore();
  final AudioPlayer _player = AudioPlayer();
  final QueueItemIdentity _queueItemIdentity = QueueItemIdentity();
  final StreamController<double> _volumeController =
      StreamController<double>.broadcast();
  final List<StreamSubscription<Object?>> _subscriptions = [];
  Future<void> _reportQueue = Future.value();
  Future<void> _navigation = Future.value();
  final Set<String> _pendingHistorySync = {};
  JellyfinSession? _session;
  List<Track> _queue = [];
  List<String> _playlistItemIds = [];
  final Map<String, Track> _tracksById = {};
  final PlaybackHistory _history = PlaybackHistory();
  bool _loadingSources = false;
  bool _smallStreaming = false;
  bool _normalization = false;
  double _userVolume = 1;
  double _normalizationMultiplier = 1;
  bool _shuffle = false;
  LoopMode _loopMode = LoopMode.off;
  String? _reportedTrackId;
  String? _reportedPlaylistItemId;
  String? _playSessionId;
  int _lastReportedSecond = -1;
  int _lastSavedSecond = -1;
  List<Track> _context = const [];
  int _contextStart = 0;
  int _contextEnd = 0;
  bool _extendingQueue = false;
  final math.Random _random = math.Random();

  static const _initialQueueSize = 100;
  static const _queueLookBehind = 20;
  static const _queueExtensionSize = 100;
  static const _queueExtensionThreshold = 15;

  AudioPlayer get player => _player;
  double get volume => _userVolume;
  Stream<double> get volumeStream => _volumeController.stream;
  List<Track> get queue => UnmodifiableListView(_queue);
  List<Track> get history => _history.items;

  /// Mobile queue view: current track first, then remaining upcoming tracks.
  ///
  /// The underlying full [queue] is unchanged (desktop keeps showing it).
  /// Played entries before [currentIndex] are hidden here; use [history] to
  /// go back to them.
  List<Track> get upcomingQueue =>
      MobileQueueView.upcoming(_queue, currentIndex);

  /// Full-queue index backing `upcomingQueue[0]`.
  int get upcomingOffset =>
      MobileQueueView.offsetFor(currentIndex, _queue.length);
  bool get playing => _player.playing;
  bool get shuffle => _shuffle;
  LoopMode get loopMode => _loopMode;
  int? get currentIndex => _player.currentIndex;
  Track? get currentTrack {
    final tag = _player.sequenceState.currentSource?.tag;
    if (tag is MediaItem) {
      final sourceTrack = _tracksById[tag.id];
      if (sourceTrack != null) return sourceTrack;
    }
    final index = currentIndex;
    return index == null || index < 0 || index >= _queue.length
        ? null
        : _queue[index];
  }

  Future<void> configure(
    JellyfinSession session, {
    bool smallStreaming = false,
    bool normalization = false,
  }) async {
    _session = session;
    _smallStreaming = smallStreaming;
    _normalization = normalization;
    final audioSession = await AudioSession.instance;
    await audioSession.configure(const AudioSessionConfiguration.music());
    final track = currentTrack;
    if (track != null) await _applyGain(track);
  }

  Future<void> replaceQueue(
    List<Track> tracks, {
    int? startIndex,
    bool? shuffle,
  }) async {
    if (tracks.isEmpty || _session == null) return;
    if (shuffle != null) _shuffle = shuffle;
    final prepared = CollectionQueue.prepare(
      tracks,
      shuffle: _shuffle,
      random: _random,
      startIndex: startIndex,
    );
    _context = prepared.context;
    final start = math.max(0, prepared.index - _queueLookBehind);
    _contextStart = start;
    _contextEnd = math.min(_context.length, start + _initialQueueSize);
    _queue = _context.sublist(start, _contextEnd);
    _playlistItemIds = _queue.map((_) => _newPlaylistItemId()).toList();
    _rememberTracks(_queue);
    await _loadSources(initialIndex: prepared.index - start);
    unawaited(_player.play());
    unawaited(_reportProgress(force: true));
  }

  Future<void> playTrack(Track track, List<Track> context) async {
    final index = context.indexWhere((item) => item.id == track.id);
    await replaceQueue(context, startIndex: index < 0 ? 0 : index);
  }

  @override
  Future<void> addToQueue(Track track) async {
    final session = _session;
    if (session == null) return;
    _stopAutomaticQueueExpansion();
    _queue = [..._queue, track];
    _playlistItemIds.add(_newPlaylistItemId());
    _rememberTracks([track]);
    final sources = await _sources(session, [track]);
    await _player.addAudioSource(sources.single);
    await _saveQueue();
    unawaited(_reportProgress(force: true));
    notifyListeners();
  }

  @override
  Future<void> addNextToQueue(List<Track> tracks) async {
    final session = _session;
    if (session == null || tracks.isEmpty) return;
    _stopAutomaticQueueExpansion();
    final insertAt = math.min((currentIndex ?? -1) + 1, _queue.length);
    _queue.insertAll(insertAt, tracks);
    _playlistItemIds.insertAll(
      insertAt,
      tracks.map((_) => _newPlaylistItemId()),
    );
    _rememberTracks(tracks);
    await _player.insertAudioSources(insertAt, await _sources(session, tracks));
    await _saveQueue();
    unawaited(_reportProgress(force: true));
    notifyListeners();
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _stopAutomaticQueueExpansion();
    _queue.removeAt(index);
    _playlistItemIds.removeAt(index);
    await _player.removeAudioSourceAt(index);
    await _saveQueue();
    unawaited(_reportProgress(force: true));
    notifyListeners();
  }

  Future<void> removeTrack(String trackId) async {
    _stopAutomaticQueueExpansion();
    _context = _context.where((track) => track.id != trackId).toList();
    _contextEnd = math.min(_contextEnd, _context.length);
    for (var index = _queue.length - 1; index >= 0; index--) {
      if (_queue[index].id != trackId) continue;
      _queue.removeAt(index);
      _playlistItemIds.removeAt(index);
      await _player.removeAudioSourceAt(index);
    }
    _tracksById.remove(trackId);
    _history.removeTrack(trackId);
    await _saveQueue();
    unawaited(_reportProgress(force: true));
    notifyListeners();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= _queue.length ||
        newIndex < 0 ||
        newIndex >= _queue.length) {
      return;
    }
    _stopAutomaticQueueExpansion();
    final track = _queue.removeAt(oldIndex);
    final playlistItemId = _playlistItemIds.removeAt(oldIndex);
    _queue.insert(newIndex, track);
    _playlistItemIds.insert(newIndex, playlistItemId);
    await _player.moveAudioSource(oldIndex, newIndex);
    await _saveQueue();
    unawaited(_reportProgress(force: true));
    notifyListeners();
  }

  Future<void> clearHistory() async {
    if (_history.isEmpty) return;
    _history.clear();
    await _saveQueue();
    notifyListeners();
  }

  /// Plays a mobile (upcoming-view) index.
  ///
  /// Mobile index 0 is the current track; translation keeps desktop's
  /// full-queue indices untouched.
  Future<void> playUpcomingIndex(int mobileIndex) async {
    final full = MobileQueueView.toFullIndex(
      mobileIndex,
      currentIndex,
      _queue.length,
    );
    if (full < 0) return;
    await playQueueIndex(full);
  }

  /// Removes a mobile (upcoming-view) index.
  Future<void> removeUpcomingAt(int mobileIndex) async {
    final full = MobileQueueView.toFullIndex(
      mobileIndex,
      currentIndex,
      _queue.length,
    );
    if (full < 0) return;
    await removeAt(full);
  }

  /// Reorders within the mobile (upcoming-view) list.
  ///
  /// The current track stays pinned at mobile index 0: moves involving it
  /// are ignored so the mobile queue always keeps current first and only
  /// the remaining upcoming order changes.
  Future<void> reorderUpcoming(int oldMobileIndex, int newMobileIndex) async {
    final translated = MobileQueueView.reorderFullIndices(
      oldMobileIndex,
      newMobileIndex,
      currentIndex,
      _queue.length,
    );
    if (translated == null) return;
    await reorder(translated.$1, translated.$2);
  }

  Future<void> playHistoryIndex(int index) =>
      _serializeNavigation(() => _playHistoryNow(index));

  Future<void> _playHistoryNow(int index) async {
    final session = _session;
    if (session == null || index < 0 || index >= _history.items.length) {
      return;
    }
    final track = _history.items[index];
    final found =
        _findInQueueBeforeCurrent(track.id) ??
        _queue.indexWhere((item) => item.id == track.id);
    if (found >= 0) {
      await _playQueueIndexNow(found);
      return;
    }
    // History track is no longer queued: drop it (and newer entries) from
    // history, queue it next, then advance to it. The current track is
    // recorded as history by [_playQueueIndexNow] forward handling, so the
    // upcoming list never duplicates entries.
    _history.removeThrough(index);
    await addNextToQueue([track]);
    final next = currentIndex == null ? -1 : currentIndex! + 1;
    if (next >= 0 && next < _queue.length) {
      await _playQueueIndexNow(next);
    }
  }

  @override
  Future<void> toggle() async {
    if (_player.playing) {
      await _savePosition(_player.position);
      await pause();
      return;
    }
    await play();
  }

  @override
  Future<void> pause() async {
    if (!_player.playing) return;
    await _player.pause();
    unawaited(_reportProgress(force: true));
  }

  @override
  Future<void> play() async {
    if (_player.playing) return;
    unawaited(_player.play());
    unawaited(_reportProgress(force: true));
  }

  @override
  Future<void> stop() async {
    unawaited(_reportStop());
    await _player.stop();
    notifyListeners();
  }

  @override
  Future<void> next() => _serializeNavigation(_nextNow);

  Future<void> _nextNow() async {
    final index = currentIndex;
    if (index == null || _queue.isEmpty) return;
    final next = index + 1;
    if (next >= _queue.length) {
      // Queue exhaustion (or loop wrap handled by the player): keep the
      // previous just_audio behavior without manufacturing history.
      await _player.seekToNext();
      return;
    }
    _history.record(_queue[index]);
    _pendingHistorySync.add(_playlistItemIds[next]);
    await _player.seekToNext();
    await _saveQueue();
    notifyListeners();
  }

  Future<void> playQueueIndex(int index) =>
      _serializeNavigation(() => _playQueueIndexNow(index));

  Future<void> _playQueueIndexNow(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final current = currentIndex;
    if (current != null && index == current) {
      await _player.seek(Duration.zero, index: index);
      unawaited(_player.play());
      unawaited(_reportProgress(force: true));
      return;
    }
    final target = _queue[index];
    if (current != null && index > current) {
      // Forward jump: the track being left was played.
      if (current >= 0 && current < _queue.length) {
        _history.record(_queue[current]);
      }
    } else {
      // Backward jump: the target (and newer history) becomes
      // current/upcoming again, so unwind history instead of pushing.
      // Direction-first keeps duplicate track ids correct: a forward jump
      // onto a duplicate id still records, a backward jump never pushes.
      if (_history.containsId(target.id)) {
        _history.removeUpToId(target.id);
      }
    }
    _pendingHistorySync.add(_playlistItemIds[index]);
    await _player.seek(Duration.zero, index: index);
    unawaited(_player.play());
    unawaited(_reportProgress(force: true));
    await _saveQueue();
    notifyListeners();
  }

  @override
  Future<void> previous() => _serializeNavigation(_previousNow);

  Future<void> _previousNow() async {
    if (_queue.isEmpty) return;
    if (_player.position > const Duration(seconds: 4)) {
      await _player.seek(Duration.zero);
      unawaited(_reportProgress(force: true));
      return;
    }
    if (_history.isEmpty) {
      // No recorded history: preserve the old seekToPrevious fallback but
      // suppress the automatic history push so the upcoming list and
      // history stay distinct.
      final index = currentIndex;
      if (index != null && index - 1 >= 0) {
        _pendingHistorySync.add(_playlistItemIds[index - 1]);
      }
      await _player.seekToPrevious();
      return;
    }
    final target = _history.mostRecent;
    if (target == null) {
      await _player.seekToPrevious();
      return;
    }
    final found =
        _findInQueueBeforeCurrent(target.id) ??
        _queue.indexWhere((item) => item.id == target.id);
    if (found < 0) {
      // History entry is no longer queued: drop it instead of stalling,
      // then fall back to the player behavior.
      _history.takeFirst();
      await _saveQueue();
      notifyListeners();
      await _player.seekToPrevious();
      return;
    }
    _history.takeFirst();
    _pendingHistorySync.add(_playlistItemIds[found]);
    await _player.seek(Duration.zero, index: found);
    unawaited(_player.play());
    unawaited(_reportProgress(force: true));
    await _saveQueue();
    notifyListeners();
  }

  int? _findInQueueBeforeCurrent(String trackId) {
    final current = currentIndex;
    if (current == null) return null;
    for (var i = current - 1; i >= 0; i--) {
      if (_queue[i].id == trackId) return i;
    }
    return null;
  }

  Future<void> _serializeNavigation(Future<void> Function() task) {
    final result = _navigation.then((_) => task());
    _navigation = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    await _savePosition(position);
    unawaited(_reportProgress(force: true));
  }

  @override
  Future<void> setVolume(double volume) async {
    _userVolume = volume.clamp(0.0, 1.0);
    _volumeController.add(_userVolume);
    await _updateOutputVolume();
    unawaited(_reportProgress(force: true));
  }

  Future<void> toggleShuffle() async {
    if (_shuffle) {
      _shuffle = false;
      await _player.setShuffleModeEnabled(false);
      await _saveQueue();
      unawaited(_reportProgress(force: true));
      notifyListeners();
      return;
    }
    _shuffle = true;
    await _player.setShuffleModeEnabled(false);
    final index = currentIndex;
    if (index == null || _queue.isEmpty) {
      await _saveQueue();
      unawaited(_reportProgress(force: true));
      notifyListeners();
      return;
    }
    while (_extendingQueue) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
    _extendingQueue = true;
    try {
      final position = _player.position;
      final wasPlaying = _player.playing;
      _shuffleRemainder(index);
      await _loadSources(initialIndex: index, initialPosition: position);
      if (wasPlaying) unawaited(_player.play());
    } finally {
      _extendingQueue = false;
    }
    unawaited(_reportProgress(force: true));
    notifyListeners();
  }

  void _shuffleRemainder(int currentIndex) {
    final queueSuffix = _queue.sublist(currentIndex + 1);
    final idSuffix = _playlistItemIds.sublist(currentIndex + 1);
    final tail = _contextEnd < _context.length
        ? _context.sublist(_contextEnd)
        : <Track>[];
    final shuffled = CollectionQueue.shuffleRemainder(
      queueSuffix: queueSuffix,
      idSuffix: idSuffix,
      tail: tail,
      random: _random,
      newId: _newPlaylistItemId,
    );
    _queue = [..._queue.sublist(0, currentIndex + 1), ...shuffled.queueTracks];
    _playlistItemIds = [
      ..._playlistItemIds.sublist(0, currentIndex + 1),
      ...shuffled.queueIds,
    ];
    final prefixLength = _contextStart + currentIndex + 1;
    _context = [
      ..._context.sublist(0, prefixLength),
      ...shuffled.queueTracks,
      ...shuffled.tail,
    ];
    _rememberTracks(shuffled.queueTracks);
    _rememberTracks(shuffled.tail);
  }

  Future<void> cycleRepeat() async {
    _loopMode = switch (_loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await _player.setLoopMode(_loopMode);
    unawaited(_reportProgress(force: true));
    notifyListeners();
  }

  @override
  Future<void> setShuffle(bool enabled) async {
    if (_shuffle == enabled) return;
    await toggleShuffle();
  }

  @override
  Future<void> setRepeatMode(LoopMode mode) async {
    if (_loopMode == mode) return;
    _loopMode = mode;
    await _player.setLoopMode(mode);
    unawaited(_reportProgress(force: true));
    notifyListeners();
  }

  @override
  Future<void> takeOver(
    List<Track> tracks, {
    required int startIndex,
    required Duration position,
  }) async {
    if (tracks.isEmpty || _session == null) return;
    final safeIndex = startIndex.clamp(0, tracks.length - 1);
    _context = List.of(tracks);
    _contextStart = 0;
    _contextEnd = tracks.length;
    _queue = List.of(tracks);
    _playlistItemIds = tracks.map((_) => _newPlaylistItemId()).toList();
    _rememberTracks(tracks);
    final duration = Duration(
      microseconds: tracks[safeIndex].durationTicks ~/ 10,
    );
    final safePosition = position > duration ? duration : position;
    await _loadSources(initialIndex: safeIndex, initialPosition: safePosition);
    unawaited(_player.play());
    unawaited(_reportProgress(force: true));
  }

  Future<void> restore(List<Track> catalog) async {
    final session = _session;
    if (session == null || catalog.isEmpty) return;
    final encoded = await _stateStore.read(_accountId(session));
    if (encoded == null) return;
    final snapshot = jsonDecode(encoded) as Map<String, dynamic>;
    final ids = (snapshot['queue'] as List<dynamic>? ?? const [])
        .cast<String>();
    final byId = {for (final track in catalog) track.id: track};
    _queue = ids.map((id) => byId[id]).whereType<Track>().toList();
    if (_queue.isEmpty) return;
    final historyIds = (snapshot['history'] as List<dynamic>? ?? const [])
        .cast<String>();
    final restoredHistory = historyIds
        .map((id) => byId[id])
        .whereType<Track>()
        .toList();
    _history.load(restoredHistory);
    _shuffle = snapshot['shuffle'] as bool? ?? false;
    _playlistItemIds = _queue.map((_) => _newPlaylistItemId()).toList();
    _rememberTracks(_queue);
    _rememberTracks(restoredHistory);
    _context = List.of(_queue);
    _contextStart = 0;
    _contextEnd = _context.length;
    final index = snapshot['index'] as int? ?? 0;
    final milliseconds = snapshot['positionMilliseconds'] as int? ?? 0;
    await _loadSources(
      initialIndex: index.clamp(0, _queue.length - 1),
      initialPosition: Duration(milliseconds: milliseconds),
    );
    await _player.pause();
    await _savePosition(_player.position);
  }

  Future<void> clear() async {
    final session = _session;
    unawaited(_reportStop());
    await _player.stop();
    _queue = [];
    _playlistItemIds = [];
    _history.clear();
    _tracksById.clear();
    _context = const [];
    _contextStart = 0;
    _contextEnd = 0;
    _shuffle = false;
    _loopMode = LoopMode.off;
    _session = null;
    if (session != null) await _stateStore.clear(_accountId(session));
    notifyListeners();
  }

  Future<void> _loadSources({
    required int initialIndex,
    Duration initialPosition = Duration.zero,
  }) async {
    final session = _session!;
    _loadingSources = true;
    try {
      await _player.stop();
      await _player.clearAudioSources();
      await _player.setAudioSources(
        await _sources(session, _queue),
        initialIndex: initialIndex,
        initialPosition: initialPosition,
      );
      await _player.setShuffleModeEnabled(false);
      await _player.seek(initialPosition, index: initialIndex);
    } finally {
      _loadingSources = false;
    }
    await _handleTrackChange();
    await _saveQueue();
    notifyListeners();
  }

  Future<List<AudioSource>> _sources(
    JellyfinSession session,
    List<Track> tracks,
  ) async {
    final local = await _downloads.resolveAll(tracks.map((track) => track.id));
    return tracks
        .map((track) => _source(session, track, local[track.id]))
        .toList(growable: false);
  }

  AudioSource _source(JellyfinSession session, Track track, [Uri? local]) {
    return AudioSource.uri(
      local ?? _client.streamUri(session, track.id, small: _smallStreaming),
      tag: MediaItem(
        id: track.id,
        title: track.name,
        artist: track.artist,
        album: track.album,
        duration: Duration(microseconds: track.durationTicks ~/ 10),
        artUri: _client.imageUri(session, track.albumId ?? track.id),
      ),
    );
  }

  Future<void> _saveQueue() async {
    await _savePosition(_player.position);
  }

  Future<void> _savePosition(Duration position) async {
    if (_queue.isEmpty) return;
    final session = _session;
    if (session == null) return;
    await _stateStore.write(
      _accountId(session),
      jsonEncode({
        'queue': _queue.map((track) => track.id).toList(),
        'index': currentIndex ?? 0,
        'positionMilliseconds': position.inMilliseconds,
        'shuffle': _shuffle,
        'history': _history.toIds(),
      }),
    );
  }

  String _accountId(JellyfinSession session) =>
      '${session.serverId}.${session.userId}';

  Future<void> _handleTrackChange() async {
    final track = currentTrack;
    final session = _session;
    final playlistItemId = _currentPlaylistItemId;
    if (track == null ||
        session == null ||
        track.id == _reportedTrackId &&
            playlistItemId == _reportedPlaylistItemId) {
      return;
    }
    // Manual navigations (next/previous/direct selection/history replay)
    // already keep history in sync synchronously and register the target
    // playlist item here. Skipping the automatic record keeps queue display
    // and history distinct: going back never duplicates the upcoming list.
    if (playlistItemId != null && _pendingHistorySync.remove(playlistItemId)) {
      // History already updated by the navigation itself.
    } else {
      _recordHistory();
    }
    unawaited(_extendQueueIfNeeded());
    await _applyGain(track);
    unawaited(_reportStop());
    _reportedTrackId = track.id;
    _reportedPlaylistItemId = playlistItemId;
    final playSessionId =
        '${DateTime.now().microsecondsSinceEpoch}-${track.id}';
    _playSessionId = playSessionId;
    _lastReportedSecond = -1;
    unawaited(
      _serializeReport(() async {
        try {
          await _client.reportPlayback(
            session,
            '/Sessions/Playing',
            track.id,
            _player.position,
            playSessionId: playSessionId,
            paused: !_player.playing,
            playlistItemId: playlistItemId,
            queue: _reportedQueue,
            volume: (_userVolume * 100).round(),
            repeatMode: _reportedRepeatMode,
            shuffle: _shuffle,
          );
        } catch (_) {}
      }),
    );
  }

  Future<void> _extendQueueIfNeeded() async {
    final session = _session;
    final index = currentIndex;
    if (session == null ||
        index == null ||
        _extendingQueue ||
        _contextEnd >= _context.length ||
        _queue.length - index > _queueExtensionThreshold) {
      return;
    }
    _extendingQueue = true;
    try {
      final end = math.min(_context.length, _contextEnd + _queueExtensionSize);
      final tracks = _context.sublist(_contextEnd, end);
      _rememberTracks(tracks);
      await _player.addAudioSources(await _sources(session, tracks));
      _queue = [..._queue, ...tracks];
      _playlistItemIds.addAll(tracks.map((_) => _newPlaylistItemId()));
      _contextEnd = end;
      await _saveQueue();
      notifyListeners();
    } finally {
      _extendingQueue = false;
    }
  }

  void _stopAutomaticQueueExpansion() {
    _context = const [];
    _contextStart = 0;
    _contextEnd = 0;
  }

  void _rememberTracks(Iterable<Track> tracks) {
    for (final track in tracks) {
      _tracksById[track.id] = track;
    }
  }

  Future<void> _applyGain(Track track) async {
    if (!_normalization) {
      _normalizationMultiplier = 1;
      await _updateOutputVolume();
      return;
    }
    final albumQueue =
        _queue.isNotEmpty &&
        _queue.every(
          (item) => item.albumId != null && item.albumId == track.albumId,
        );
    final gain = albumQueue
        ? track.albumNormalizationGain
        : track.normalizationGain;
    if (gain == null) {
      _normalizationMultiplier = 1;
      await _updateOutputVolume();
      return;
    }
    _normalizationMultiplier = math
        .pow(10, gain / 20)
        .toDouble()
        .clamp(0.0, 1.0)
        .toDouble();
    await _updateOutputVolume();
  }

  Future<void> _updateOutputVolume() =>
      _player.setVolume(_userVolume * _normalizationMultiplier);

  Future<void> _reportProgress({bool force = false}) =>
      _serializeReport(() => _reportProgressNow(force: force));

  Future<void> _reportProgressNow({required bool force}) async {
    final session = _session;
    final trackId = _reportedTrackId;
    final playSessionId = _playSessionId;
    final second = _player.position.inSeconds;
    if (session == null || trackId == null || playSessionId == null) return;
    if (!force && second == _lastReportedSecond) return;
    _lastReportedSecond = second;
    try {
      await _client.reportPlayback(
        session,
        '/Sessions/Playing/Progress',
        trackId,
        _player.position,
        playSessionId: playSessionId,
        paused: !_player.playing,
        playlistItemId: _currentPlaylistItemId,
        queue: _reportedQueue,
        volume: (_userVolume * 100).round(),
        repeatMode: _reportedRepeatMode,
        shuffle: _shuffle,
      );
    } catch (_) {}
  }

  String? get _currentPlaylistItemId {
    final index = currentIndex;
    return index == null || index < 0 || index >= _playlistItemIds.length
        ? null
        : _playlistItemIds[index];
  }

  List<Map<String, String>> get _reportedQueue => [
    for (var index = 0; index < _queue.length; index++)
      {'Id': _queue[index].id, 'PlaylistItemId': _playlistItemIds[index]},
  ];

  String get _reportedRepeatMode => switch (_loopMode) {
    LoopMode.off => 'RepeatNone',
    LoopMode.all => 'RepeatAll',
    LoopMode.one => 'RepeatOne',
  };

  String _newPlaylistItemId() => _queueItemIdentity.next();

  Future<void> _reportStop() {
    final session = _session;
    final trackId = _reportedTrackId;
    final playSessionId = _playSessionId;
    _reportedTrackId = null;
    _reportedPlaylistItemId = null;
    _playSessionId = null;
    if (session == null || trackId == null || playSessionId == null) {
      return Future.value();
    }
    final position = _player.position;
    return _serializeReport(() async {
      try {
        await _client.reportPlayback(
          session,
          '/Sessions/Playing/Stopped',
          trackId,
          position,
          playSessionId: playSessionId,
        );
      } catch (_) {}
    });
  }

  void _recordHistory() {
    final previousId = _reportedTrackId;
    if (previousId == null) return;
    final previous = _tracksById[previousId];
    if (previous == null) return;
    _history.record(previous);
  }

  Future<void> _finishCompletedQueue() async {
    _recordHistory();
    unawaited(_reportStop());
    await _player.stop();
    await _saveQueue();
    notifyListeners();
  }

  Future<void> _serializeReport(Future<void> Function() report) {
    final result = _reportQueue.then((_) => report());
    _reportQueue = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _volumeController.close();
    _player.dispose();
    super.dispose();
  }
}
