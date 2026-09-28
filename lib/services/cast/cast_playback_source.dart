import '../../storage/database.dart';
import '../playback/playback_snapshot.dart';

/// Minimal playback surface the Cast controller needs.
///
/// Implemented by [PlaybackServiceCastSource] for production and by fakes in
/// tests, so `flutter test` never touches `just_audio`.
abstract interface class CastPlaybackSource {
  Track? get currentTrack;
  List<Track> get queue;
  int? get currentIndex;
  Duration get position;

  /// Whether local audio currently reports playing.
  bool get playing;

  /// Halt local audio for handoff. Sends the phone Jellyfin session to
  /// Stopped so only the receiver reports while casting.
  Future<void> stopForCast();

  Future<void> playQueueIndex(int index);
  Future<void> seek(Duration position);
  Future<void> play();
  Future<void> pause();

  /// Suppresses local Jellyfin progress reports while the receiver owns
  /// playback (see `PlaybackService.setCastingActive`).
  void setCastingActive(bool active);

  /// Captures an atomic local snapshot for handoff and recovery.
  PlaybackSnapshot captureSnapshot();

  /// Restores a snapshot atomically, retaining occurrence ids.
  Future<void> restoreSnapshot(PlaybackSnapshot snapshot);

  /// Reports the currently committed local state on the serialized path.
  Future<void> reportCurrentState();
}
