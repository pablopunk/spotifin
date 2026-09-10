import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../storage/database.dart';
import '../downloads/download_service.dart';
import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/session.dart';

class PlaybackService extends ChangeNotifier {
  PlaybackService(this._client, this._downloads) {
    _subscriptions.add(
      _player.playerStateStream.listen((playerState) {
        _reportProgress();
        if (playerState.processingState == ProcessingState.completed) {
          _reportStop();
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
        if (second % 10 == 0 && second != _lastSavedSecond) {
          _lastSavedSecond = second;
          _savePosition(position);
          _reportProgress();
        }
      }),
    );
  }

  final JellyfinClient _client;
  final DownloadService _downloads;
  final AudioPlayer _player = AudioPlayer();
  final StreamController<double> _volumeController =
      StreamController<double>.broadcast();
  final List<StreamSubscription<Object?>> _subscriptions = [];
  JellyfinSession? _session;
  List<Track> _queue = [];
  final Map<String, Track> _tracksById = {};
  bool _loadingSources = false;
  bool _smallStreaming = false;
  bool _normalization = true;
  double _userVolume = 1;
  double _normalizationMultiplier = 1;
  bool _shuffle = false;
  LoopMode _loopMode = LoopMode.off;
  String? _reportedTrackId;
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
    bool normalization = true,
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
    _rememberTracks(_queue);
    await _loadSources(initialIndex: safeIndex - start);
    await _player.play();
  }

  Future<void> playTrack(Track track, List<Track> context) async {
    final index = context.indexWhere((item) => item.id == track.id);
    await replaceQueue(context, startIndex: index < 0 ? 0 : index);
  }

  Future<void> addToQueue(Track track) async {
    final session = _session;
    if (session == null) return;
    _stopAutomaticQueueExpansion();
    _queue = [..._queue, track];
    _rememberTracks([track]);
    final sources = await _sources(session, [track]);
    await _player.addAudioSource(sources.single);
    await _saveQueue();
    notifyListeners();
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _stopAutomaticQueueExpansion();
    _queue.removeAt(index);
    await _player.removeAudioSourceAt(index);
    await _saveQueue();
    notifyListeners();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    _stopAutomaticQueueExpansion();
    final track = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, track);
    await _player.moveAudioSource(oldIndex, newIndex);
    await _saveQueue();
    notifyListeners();
  }

  Future<void> toggle() => _player.playing ? _player.pause() : _player.play();
  Future<void> next() => _player.seekToNext();
  Future<void> previous() async {
    if (_player.position > const Duration(seconds: 4)) {
      await _player.seek(Duration.zero);
    } else {
      await _player.seekToPrevious();
    }
  }

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> setVolume(double volume) async {
    _userVolume = volume.clamp(0.0, 1.0);
    _volumeController.add(_userVolume);
    await _updateOutputVolume();
  }

  Future<void> toggleShuffle() async {
    _shuffle = !_shuffle;
    await _player.setShuffleModeEnabled(_shuffle);
    if (_shuffle) await _player.shuffle();
    notifyListeners();
  }

  Future<void> cycleRepeat() async {
    _loopMode = switch (_loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await _player.setLoopMode(_loopMode);
    notifyListeners();
  }

  Future<void> restore(List<Track> catalog) async {
    final session = _session;
    if (session == null || catalog.isEmpty) return;
    final preferences = await SharedPreferences.getInstance();
    final ids = (jsonDecode(
      preferences.getString('queue') ?? '[]',
    ) as List<dynamic>).cast<String>();
    final byId = {for (final track in catalog) track.id: track};
    _queue = ids.map((id) => byId[id]).whereType<Track>().toList();
    if (_queue.isEmpty) return;
    _rememberTracks(_queue);
    _context = List.of(_queue);
    _contextEnd = _context.length;
    final index = preferences.getInt('queueIndex') ?? 0;
    final milliseconds = preferences.getInt('queuePosition') ?? 0;
    await _loadSources(
      initialIndex: index.clamp(0, _queue.length - 1),
      initialPosition: Duration(milliseconds: milliseconds),
    );
    await _player.pause();
  }

  Future<void> clear() async {
    await _reportStop();
    await _player.stop();
    _queue = [];
    _tracksById.clear();
    _context = const [];
    _contextEnd = 0;
    _session = null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('queue');
    await preferences.remove('queueIndex');
    await preferences.remove('queuePosition');
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
      ),
    );
  }

  Future<void> _saveQueue() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'queue',
      jsonEncode(_queue.map((track) => track.id).toList()),
    );
    await preferences.setInt('queueIndex', currentIndex ?? 0);
    await _savePosition(_player.position);
  }

  Future<void> _savePosition(Duration position) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt('queuePosition', position.inMilliseconds);
  }

  Future<void> _handleTrackChange() async {
    final track = currentTrack;
    final session = _session;
    if (track == null || session == null || track.id == _reportedTrackId) {
      return;
    }
    unawaited(_extendQueueIfNeeded());
    await _applyGain(track);
    await _reportStop();
    _reportedTrackId = track.id;
    _playSessionId = '${DateTime.now().microsecondsSinceEpoch}-${track.id}';
    _lastReportedSecond = -1;
    try {
      await _client.reportPlayback(
        session,
        '/Sessions/Playing',
        track.id,
        _player.position,
        playSessionId: _playSessionId!,
        paused: !_player.playing,
      );
    } catch (_) {}
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

  Future<void> _reportProgress() async {
    final session = _session;
    final trackId = _reportedTrackId;
    final playSessionId = _playSessionId;
    final second = _player.position.inSeconds;
    if (session == null || trackId == null || playSessionId == null) return;
    if (second == _lastReportedSecond) return;
    _lastReportedSecond = second;
    try {
      await _client.reportPlayback(
        session,
        '/Sessions/Playing/Progress',
        trackId,
        _player.position,
        playSessionId: playSessionId,
        paused: !_player.playing,
      );
    } catch (_) {}
  }

  Future<void> _reportStop() async {
    final session = _session;
    final trackId = _reportedTrackId;
    final playSessionId = _playSessionId;
    if (session == null || trackId == null || playSessionId == null) return;
    _reportedTrackId = null;
    _playSessionId = null;
    try {
      await _client.reportPlayback(
        session,
        '/Sessions/Playing/Stopped',
        trackId,
        _player.position,
        playSessionId: playSessionId,
      );
    } catch (_) {}
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
