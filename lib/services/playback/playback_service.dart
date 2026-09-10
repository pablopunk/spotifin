import 'dart:async';
import 'dart:convert';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../storage/database.dart';
import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/session.dart';

class PlaybackService extends ChangeNotifier {
  PlaybackService(this._client) {
    _subscriptions.add(
      _player.playerStateStream.listen((_) => notifyListeners()),
    );
    _subscriptions.add(
      _player.currentIndexStream.listen((_) {
        _saveQueue();
        notifyListeners();
      }),
    );
    _subscriptions.add(
      _player.positionStream.listen((position) {
        if (position.inSeconds % 10 == 0) _savePosition(position);
      }),
    );
  }

  final JellyfinClient _client;
  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<Object?>> _subscriptions = [];
  JellyfinSession? _session;
  List<Track> _queue = [];
  bool _smallStreaming = false;
  bool _shuffle = false;
  LoopMode _loopMode = LoopMode.off;

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
  }) async {
    _session = session;
    _smallStreaming = smallStreaming;
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
    await _player.addAudioSource(_source(session, track));
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
      _queue.map((track) => _source(session, track)).toList(),
      initialIndex: initialIndex,
      initialPosition: initialPosition,
    );
    await _saveQueue();
  }

  AudioSource _source(JellyfinSession session, Track track) => AudioSource.uri(
    _client.streamUri(session, track.id, small: _smallStreaming),
    tag: track.id,
  );

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

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _player.dispose();
    super.dispose();
  }
}
