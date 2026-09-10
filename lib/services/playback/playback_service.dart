import 'dart:async';
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
        _handleTrackChange();
        _saveQueue();
        notifyListeners();
      }),
    );
    _subscriptions.add(
      _player.positionStream.listen((position) {
        if (position.inSeconds % 10 == 0) {
          _savePosition(position);
          _reportProgress();
        }
      }),
    );
  }

  final JellyfinClient _client;
  final DownloadService _downloads;
  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<Object?>> _subscriptions = [];
  JellyfinSession? _session;
  List<Track> _queue = [];
  bool _smallStreaming = false;
  bool _normalization = true;
  bool _shuffle = false;
  LoopMode _loopMode = LoopMode.off;
  String? _reportedTrackId;
  String? _playSessionId;
  int _lastReportedSecond = -1;

  AudioPlayer get player => _player;
  List<Track> get queue => List.unmodifiable(_queue);
  bool get playing => _player.playing;
  bool get shuffle => _shuffle;
  LoopMode get loopMode => _loopMode;
  int? get currentIndex => _player.currentIndex;
  Track? get currentTrack {
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
  }

  Future<void> replaceQueue(List<Track> tracks, {int startIndex = 0}) async {
    if (tracks.isEmpty || _session == null) return;
    _queue = List.of(tracks);
    await _loadSources(initialIndex: startIndex);
    await _player.play();
  }

  Future<void> playTrack(Track track, List<Track> context) async {
    final index = context.indexWhere((item) => item.id == track.id);
    await replaceQueue(context, startIndex: index < 0 ? 0 : index);
  }

  Future<void> addToQueue(Track track) async {
    final session = _session;
    if (session == null) return;
    _queue = [..._queue, track];
    await _player.addAudioSource(await _source(session, track));
    await _saveQueue();
    notifyListeners();
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    await _player.removeAudioSourceAt(index);
    await _saveQueue();
    notifyListeners();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
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
    await _player.setAudioSources(
      await Future.wait(_queue.map((track) => _source(session, track))),
      initialIndex: initialIndex,
      initialPosition: initialPosition,
    );
    await _saveQueue();
  }

  Future<AudioSource> _source(JellyfinSession session, Track track) async {
    final local = await _downloads.resolve(track.id);
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

  Future<void> _applyGain(Track track) async {
    if (!_normalization) {
      await _player.setVolume(1);
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
      await _player.setVolume(1);
      return;
    }
    final multiplier = math
        .pow(10, gain / 20)
        .toDouble()
        .clamp(0.0, 1.0)
        .toDouble();
    await _player.setVolume(multiplier);
  }

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
    _player.dispose();
    super.dispose();
  }
}
