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
  JellyfinSession? _session;
  List<Track> _queue = [];
  List<String> _playlistItemIds = [];
  final Map<String, Track> _tracksById = {};
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
  int _contextEnd = 0;
  bool _extendingQueue = false;

  static const _initialQueueSize = 100;
  static const _queueLookBehind = 20;
  static const _queueExtensionSize = 100;
  static const _queueExtensionThreshold = 15;

  AudioPlayer get player => _player;
  double get volume => _userVolume;
  Stream<double> get volumeStream => _volumeController.stream;
  List<Track> get queue => UnmodifiableListView(_queue);
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

  Future<void> replaceQueue(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty || _session == null) return;
    final safeIndex = startIndex.clamp(0, tracks.length - 1);
    final start = math.max(0, safeIndex - _queueLookBehind);
    _context = List.of(tracks);
    _contextEnd = math.min(tracks.length, start + _initialQueueSize);
    _queue = _context.sublist(start, _contextEnd);
    _playlistItemIds = _queue.map((_) => _newPlaylistItemId()).toList();
    _rememberTracks(_queue);
    await _loadSources(initialIndex: safeIndex - start);
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
    await _saveQueue();
    unawaited(_reportProgress(force: true));
    notifyListeners();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
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
  Future<void> next() => _player.seekToNext();

  Future<void> playQueueIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;
    await _player.seek(Duration.zero, index: index);
    unawaited(_player.play());
    unawaited(_reportProgress(force: true));
  }

  @override
  Future<void> previous() async {
    if (_player.position > const Duration(seconds: 4)) {
      await _player.seek(Duration.zero);
      unawaited(_reportProgress(force: true));
    } else {
      await _player.seekToPrevious();
    }
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
    _shuffle = !_shuffle;
    await _player.setShuffleModeEnabled(_shuffle);
    if (_shuffle) await _player.shuffle();
    unawaited(_reportProgress(force: true));
    notifyListeners();
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
    _playlistItemIds = _queue.map((_) => _newPlaylistItemId()).toList();
    _rememberTracks(_queue);
    _context = List.of(_queue);
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
    _tracksById.clear();
    _context = const [];
    _contextEnd = 0;
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

  Future<void> _finishCompletedQueue() async {
    unawaited(_reportStop());
    await _player.stop();
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
