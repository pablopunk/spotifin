import 'package:flutter/foundation.dart';
import 'package:spotifin/services/playback/active_playback.dart';
import 'package:spotifin/services/playback/active_playback_state.dart';
import 'package:spotifin/storage/database.dart';

/// Notifying fake [ActivePlayback] for widget and routing tests.
///
/// Publishes complete states via [emit] and records every action call in
/// [actions]. Never calls the production constructor or creates native
/// adapters. All state fields start from safe empty defaults.
class FakeActivePlayback extends ChangeNotifier implements ActivePlayback {
  ActivePlaybackState _state = const ActivePlaybackState.empty();

  /// Action names in call order (for example `toggle`, `seek`).
  final List<String> actions = [];

  /// Recorded positional arguments by action name.
  final Map<String, List<Object?>> actionArguments = {};

  /// Emits a complete owner state to listeners.
  void emit(ActivePlaybackState state) {
    _state = state;
    notifyListeners();
  }

  void _record(String action, [List<Object?> arguments = const []]) {
    actions.add(action);
    actionArguments[action] = arguments;
  }

  @override
  ActivePlaybackState get state => _state;

  @override
  Future<void> toggle() async {
    _record('toggle');
  }

  @override
  Future<void> play() async {
    _record('play');
  }

  @override
  Future<void> pause() async {
    _record('pause');
  }

  @override
  Future<void> next() async {
    _record('next');
  }

  @override
  Future<void> previous() async {
    _record('previous');
  }

  @override
  Future<void> seek(Duration position) async {
    _record('seek', [position]);
  }

  @override
  Future<void> setVolumeSlider(double slider) async {
    _record('setVolumeSlider', [slider]);
  }

  @override
  Future<void> replaceQueue(
    List<Track> tracks, {
    int? startIndex,
    bool? shuffle,
  }) async {
    _record('replaceQueue', [tracks, startIndex, shuffle]);
  }

  @override
  Future<void> playTrack(Track track, List<Track> context) async {
    _record('playTrack', [track, context]);
  }

  @override
  Future<void> playQueueIndex(int index) async {
    _record('playQueueIndex', [index]);
  }

  @override
  Future<void> playUpcomingIndex(int mobileIndex) async {
    _record('playUpcomingIndex', [mobileIndex]);
  }

  @override
  Future<void> addToQueue(Track track) async {
    _record('addToQueue', [track]);
  }

  @override
  Future<void> addNextToQueue(List<Track> tracks) async {
    _record('addNextToQueue', [tracks]);
  }

  @override
  Future<void> removeAt(int index) async {
    _record('removeAt', [index]);
  }

  @override
  Future<void> removeTrack(String trackId) async {
    _record('removeTrack', [trackId]);
  }

  @override
  Future<void> removeUpcomingAt(int mobileIndex) async {
    _record('removeUpcomingAt', [mobileIndex]);
  }

  @override
  Future<void> reorder(int oldIndex, int newIndex) async {
    _record('reorder', [oldIndex, newIndex]);
  }

  @override
  Future<void> reorderUpcoming(int oldMobileIndex, int newMobileIndex) async {
    _record('reorderUpcoming', [oldMobileIndex, newMobileIndex]);
  }

  @override
  Future<void> playHistoryTrack(Track track) async {
    _record('playHistoryTrack', [track]);
  }

  @override
  Future<void> toggleShuffle() async {
    _record('toggleShuffle');
  }

  @override
  Future<void> cycleRepeat() async {
    _record('cycleRepeat');
  }

  @override
  Future<void> resumeHere() async {
    _record('resumeHere');
  }
}
