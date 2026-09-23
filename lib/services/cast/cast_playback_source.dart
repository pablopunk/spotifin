import '../../storage/database.dart';

/// Minimal playback surface the Cast controller needs.
///
/// Implemented by [PlaybackServiceCastSource] for production and by fakes in
/// tests, so `flutter test` never touches `just_audio`.
abstract interface class CastPlaybackSource {
  Track? get currentTrack;
  List<Track> get queue;
  int? get currentIndex;
  Duration get position;

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
}
