import '../../storage/database.dart';
import '../playback/playback_service.dart';
import 'cast_playback_source.dart';

/// Production [CastPlaybackSource] backed by [PlaybackService].
///
/// Handoff stops (not pauses) local audio so the phone Jellyfin session ends
/// and only the Chromecast receiver reports. Queue/history objects are left
/// untouched; resume reuses the unchanged queue via `playQueueIndex`/`seek`.
class PlaybackServiceCastSource implements CastPlaybackSource {
  PlaybackServiceCastSource(this._playback);

  final PlaybackService _playback;

  @override
  Track? get currentTrack => _playback.currentTrack;

  @override
  List<Track> get queue => _playback.queue;

  @override
  int? get currentIndex => _playback.currentIndex;

  @override
  Duration get position => _playback.player.position;

  @override
  Future<void> stopForCast() => _playback.stop();

  @override
  Future<void> playQueueIndex(int index) => _playback.playQueueIndex(index);

  @override
  Future<void> seek(Duration position) => _playback.seek(position);

  @override
  Future<void> play() => _playback.play();

  @override
  Future<void> pause() => _playback.pause();

  @override
  void setCastingActive(bool active) => _playback.setCastingActive(active);
}
