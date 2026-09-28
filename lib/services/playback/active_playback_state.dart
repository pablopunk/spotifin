import 'package:just_audio/just_audio.dart';

import '../../storage/database.dart';

/// Which adapter [ActivePlayback] routes ordinary actions to.
enum PlaybackDestination { local, cast }

/// One ordinary action family gated by [ActivePlaybackState.capabilities].
enum PlaybackCapability {
  transport,
  seek,
  volume,
  selection,
  queueEditing,
  shuffle,
  repeat,
}

/// Immutable snapshot of the active playback surface.
///
/// Consumers read one snapshot instead of choosing between local and Cast
/// state. Every event from either adapter publishes a complete new state.
class ActivePlaybackState {
  const ActivePlaybackState({
    required this.destination,
    this.track,
    this.index,
    this.entryId,
    required this.queue,
    required this.upcoming,
    required this.upcomingOffset,
    required this.history,
    required this.playing,
    required this.position,
    this.duration,
    required this.volumeSlider,
    required this.shuffle,
    required this.repeatMode,
    required this.busy,
    required this.recovering,
    this.error,
    required this.capabilities,
  });

  const ActivePlaybackState.empty()
    : destination = PlaybackDestination.local,
      track = null,
      index = null,
      entryId = null,
      queue = const [],
      upcoming = const [],
      upcomingOffset = 0,
      history = const [],
      playing = false,
      position = Duration.zero,
      duration = null,
      volumeSlider = 1,
      shuffle = false,
      repeatMode = LoopMode.off,
      busy = false,
      recovering = false,
      error = null,
      capabilities = const {};

  final PlaybackDestination destination;

  /// Current track, its loaded-queue index, and its queue occurrence id.
  final Track? track;
  final int? index;
  final String? entryId;

  /// Full loaded queue plus the current-first upcoming view and its offset.
  final List<Track> queue;
  final List<Track> upcoming;
  final int upcomingOffset;

  /// Temporary session history overlay.
  final List<Track> history;

  final bool playing;
  final Duration position;
  final Duration? duration;

  /// Linear UI slider position. Local gain conversion is applied by the
  /// owner; Cast volume is linear end to end.
  final double volumeSlider;

  final bool shuffle;
  final LoopMode repeatMode;

  /// Whether an owner action is in flight, and whether Cast awaits the
  /// user's recovery decision after connection loss.
  final bool busy;
  final bool recovering;

  /// Last redacted action failure, if any.
  final String? error;

  /// Action families the current destination accepts right now.
  final Set<PlaybackCapability> capabilities;
}
