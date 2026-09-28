import 'dart:collection';

import 'package:just_audio/just_audio.dart';

import '../../storage/database.dart';
import 'queue_state.dart';

/// Immutable playback snapshot for Cast handoff and recovery.
///
/// Carries the complete queue state (full collection context, loaded
/// window, current occurrence, and shuffle flag with every occurrence id
/// retained), the position/playing decision, the repeat mode, and the
/// temporary history overlay. Storage JSON stays untouched: snapshots are
/// never persisted.
class PlaybackSnapshot {
  PlaybackSnapshot({
    required this.queue,
    required this.position,
    required this.playing,
    required this.repeatMode,
    List<Track>? history,
  }) : history = UnmodifiableListView(List.of(history ?? const []));

  final QueueState queue;
  final Duration position;
  final bool playing;
  final LoopMode repeatMode;

  /// Temporary session history overlay (never persisted).
  final List<Track> history;

  PlaybackSnapshot copyWith({
    QueueState? queue,
    Duration? position,
    bool? playing,
    LoopMode? repeatMode,
    List<Track>? history,
  }) => PlaybackSnapshot(
    queue: queue ?? this.queue,
    position: position ?? this.position,
    playing: playing ?? this.playing,
    repeatMode: repeatMode ?? this.repeatMode,
    history: history ?? this.history,
  );
}
