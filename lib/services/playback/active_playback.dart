import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../storage/database.dart';
import '../cast/cast_controller.dart';
import '../redaction.dart';
import 'active_playback_state.dart';
import 'mobile_queue.dart';
import 'playback_service.dart';
import 'volume_scale.dart';

export 'active_playback_state.dart';

/// Typed rejection for actions the current destination cannot accept.
///
/// Thrown by [ActivePlayback] action methods (not only hidden in widgets)
/// when a capability is missing: frozen handoff, Cast recovery, disabled
/// Cast repeat, or an invalid index.
class PlaybackActionUnavailable implements Exception {
  const PlaybackActionUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One consistent playback surface over local and Cast adapters.
///
/// Player controls, lyrics, car adapters, and shortcuts read [state] and
/// call these actions instead of choosing a destination. Construction never
/// starts discovery or native audio; the owner keeps only its own
/// listeners and subscriptions and never disposes the borrowed adapters.
class ActivePlayback extends ChangeNotifier {
  ActivePlayback({required PlaybackService local, required CastController cast})
    : _local = local,
      _cast = cast {
    _localPosition = _local.player.position;
    _remotePosition = _cast.remotePosition;
    _local.addListener(_rebuild);
    _positionSub = _local.player.positionStream.listen((position) {
      _localPosition = position;
      _rebuild();
    });
    _volumeSub = _local.volumeStream.listen((_) => _rebuild());
    _cast.addListener(_rebuild);
    _castPositionSub = _cast.positionStream.listen((position) {
      _remotePosition = position;
      _rebuild();
    });
    _rebuild();
  }

  final PlaybackService _local;
  final CastController _cast;

  late StreamSubscription<Duration> _positionSub;
  late StreamSubscription<double> _volumeSub;
  late StreamSubscription<Duration> _castPositionSub;

  Duration _localPosition = Duration.zero;
  Duration _remotePosition = Duration.zero;
  int _inflight = 0;
  bool _disposed = false;
  String? _error;
  ActivePlaybackState _state = const ActivePlaybackState.empty();

  /// Current complete snapshot. Consumers use
  /// `ListenableBuilder(listenable: active, ...)` and never read an
  /// `AudioPlayer` or choose a destination stream themselves.
  ActivePlaybackState get state => _state;

  PlaybackDestination _destination() {
    switch (_cast.ownership) {
      case CastOwnership.local:
        return PlaybackDestination.local;
      case CastOwnership.transferring:
      case CastOwnership.remote:
      case CastOwnership.recovering:
        return PlaybackDestination.cast;
    }
  }

  Set<PlaybackCapability> _capabilities(PlaybackDestination destination) {
    switch (_cast.ownership) {
      case CastOwnership.transferring:
      case CastOwnership.recovering:
        // Ordinary actions freeze during handoff and after connection loss;
        // only the explicit transfer to local remains available.
        return const {};
      case CastOwnership.local:
        return PlaybackCapability.values.toSet();
      case CastOwnership.remote:
        return const {
          PlaybackCapability.transport,
          PlaybackCapability.seek,
          PlaybackCapability.volume,
          PlaybackCapability.selection,
          PlaybackCapability.queueEditing,
          PlaybackCapability.shuffle,
        };
    }
  }

  void _rebuild() {
    if (_disposed) return;
    final destination = _destination();
    if (destination == PlaybackDestination.local) {
      final queue = _local.queue;
      final index = _local.currentIndex;
      final track = _local.currentTrack;
      _state = ActivePlaybackState(
        destination: destination,
        track: track,
        index: index,
        entryId: _local.currentEntryId,
        queue: queue,
        upcoming: MobileQueueView.upcoming(queue, index),
        upcomingOffset: MobileQueueView.offsetFor(index, queue.length),
        history: _local.history,
        playing: _local.playing,
        position: _localPosition,
        duration: track == null
            ? null
            : Duration(microseconds: track.durationTicks ~/ 10),
        volumeSlider: sliderFromVolume(_local.volume),
        shuffle: _local.shuffle,
        repeatMode: _local.loopMode,
        busy: _inflight > 0,
        recovering: false,
        error: _error,
        capabilities: _capabilities(destination),
      );
    } else {
      final queue = _cast.castQueue;
      final index = _cast.remoteIndex;
      final track = _cast.remoteTrack;
      _state = ActivePlaybackState(
        destination: destination,
        track: track,
        index: queue.isEmpty ? null : index,
        entryId: _cast.remoteEntryId,
        queue: queue,
        upcoming: MobileQueueView.upcoming(queue, queue.isEmpty ? null : index),
        upcomingOffset: MobileQueueView.offsetFor(
          queue.isEmpty ? null : index,
          queue.length,
        ),
        history: _cast.castHistory,
        playing: _cast.remotePlaying,
        position: _remotePosition,
        duration: _cast.remoteDuration,
        volumeSlider: _cast.remoteVolume.clamp(0.0, 1.0),
        shuffle: _cast.castShuffle,
        repeatMode: _cast.castRepeatMode,
        busy: _inflight > 0,
        recovering: _cast.ownership == CastOwnership.recovering,
        error: _error,
        capabilities: _capabilities(destination),
        connectedDeviceName: destination == PlaybackDestination.local
            ? null
            : _cast.connectedDeviceName,
      );
    }
    notifyListeners();
  }

  /// Routes one ordinary action to the destination read exactly once.
  ///
  /// Disabled capabilities throw [PlaybackActionUnavailable]; adapter
  /// errors are recorded redacted on [state] and rethrown. No fallback to
  /// the other adapter happens on unsupported actions or errors.
  Future<void> _act(
    PlaybackCapability capability,
    String name,
    Future<void> Function() onLocal,
    Future<void> Function() onCast,
  ) async {
    final destination = _destination();
    final capabilities = _capabilities(destination);
    if (!capabilities.contains(capability)) {
      _error = '$name is not available right now.';
      _rebuild();
      throw PlaybackActionUnavailable(_error!);
    }
    _error = null;
    _inflight++;
    _rebuild();
    try {
      if (destination == PlaybackDestination.local) {
        await onLocal();
      } else {
        await onCast();
      }
    } catch (error) {
      _error = error is PlaybackActionUnavailable
          ? error.message
          : redactSecrets(error);
      _rebuild();
      rethrow;
    } finally {
      _inflight--;
      _rebuild();
    }
  }

  Future<void> toggle() =>
      _act(PlaybackCapability.transport, 'toggle', _local.toggle, _cast.toggle);

  Future<void> play() =>
      _act(PlaybackCapability.transport, 'play', _local.play, _cast.play);

  Future<void> pause() =>
      _act(PlaybackCapability.transport, 'pause', _local.pause, _cast.pause);

  Future<void> next() =>
      _act(PlaybackCapability.transport, 'next', _local.next, _cast.next);

  Future<void> previous() => _act(
    PlaybackCapability.transport,
    'previous',
    _local.previous,
    _cast.previous,
  );

  Future<void> seek(Duration position) => _act(
    PlaybackCapability.seek,
    'seek',
    () => _local.seek(position),
    () => _cast.seek(position),
  );

  Future<void> setVolumeSlider(double slider) => _act(
    PlaybackCapability.volume,
    'setVolumeSlider',
    () => _local.setVolume(volumeFromSlider(slider)),
    () => _cast.setVolume(slider.clamp(0.0, 1.0)),
  );

  Future<void> replaceQueue(
    List<Track> tracks, {
    int? startIndex,
    bool? shuffle,
  }) => _act(
    PlaybackCapability.selection,
    'replaceQueue',
    () => _local.replaceQueue(tracks, startIndex: startIndex, shuffle: shuffle),
    () => _cast.replaceQueue(tracks, startIndex: startIndex, shuffle: shuffle),
  );

  Future<void> playTrack(Track track, List<Track> context) => _act(
    PlaybackCapability.selection,
    'playTrack',
    () => _local.playTrack(track, context),
    () => _cast.playTrack(track, context),
  );

  Future<void> playQueueIndex(int index) => _act(
    PlaybackCapability.selection,
    'playQueueIndex',
    () => _local.playQueueIndex(index),
    () => _cast.playIndex(index),
  );

  Future<void> playUpcomingIndex(int mobileIndex) => _act(
    PlaybackCapability.selection,
    'playUpcomingIndex',
    () => _local.playUpcomingIndex(mobileIndex),
    () async {
      final full = MobileQueueView.toFullIndex(
        mobileIndex,
        _cast.remoteIndex,
        _cast.castQueue.length,
      );
      if (full < 0) {
        throw const PlaybackActionUnavailable(
          'playUpcomingIndex is not available right now.',
        );
      }
      await _cast.playIndex(full);
    },
  );

  Future<void> addToQueue(Track track) => _act(
    PlaybackCapability.queueEditing,
    'addToQueue',
    () => _local.addToQueue(track),
    () => _cast.addToQueue(track),
  );

  Future<void> addNextToQueue(List<Track> tracks) => _act(
    PlaybackCapability.queueEditing,
    'addNextToQueue',
    () => _local.addNextToQueue(tracks),
    () => _cast.addNextToQueue(tracks),
  );

  Future<void> removeAt(int index) => _act(
    PlaybackCapability.queueEditing,
    'removeAt',
    () => _local.removeAt(index),
    () => _cast.removeAt(index),
  );

  Future<void> removeTrack(String trackId) => _act(
    PlaybackCapability.queueEditing,
    'removeTrack',
    () => _local.removeTrack(trackId),
    () => _cast.removeTrack(trackId),
  );

  Future<void> removeUpcomingAt(int mobileIndex) => _act(
    PlaybackCapability.queueEditing,
    'removeUpcomingAt',
    () => _local.removeUpcomingAt(mobileIndex),
    () async {
      final full = MobileQueueView.toFullIndex(
        mobileIndex,
        _cast.remoteIndex,
        _cast.castQueue.length,
      );
      if (full < 0) {
        throw const PlaybackActionUnavailable(
          'removeUpcomingAt is not available right now.',
        );
      }
      await _cast.removeAt(full);
    },
  );

  Future<void> reorder(int oldIndex, int newIndex) => _act(
    PlaybackCapability.queueEditing,
    'reorder',
    () => _local.reorder(oldIndex, newIndex),
    () => _cast.reorder(oldIndex, newIndex),
  );

  Future<void> reorderUpcoming(int oldMobileIndex, int newMobileIndex) => _act(
    PlaybackCapability.queueEditing,
    'reorderUpcoming',
    () => _local.reorderUpcoming(oldMobileIndex, newMobileIndex),
    () async {
      // The current upcoming entry stays pinned during reorder.
      final translated = MobileQueueView.reorderFullIndices(
        oldMobileIndex,
        newMobileIndex,
        _cast.remoteIndex,
        _cast.castQueue.length,
      );
      if (translated == null) {
        throw const PlaybackActionUnavailable(
          'reorderUpcoming is not available right now.',
        );
      }
      await _cast.reorder(translated.$1, translated.$2);
    },
  );

  Future<void> playHistoryTrack(Track track) => _act(
    PlaybackCapability.selection,
    'playHistoryTrack',
    () => _local.playHistoryTrack(track),
    () => _cast.playHistoryTrack(track),
  );

  Future<void> toggleShuffle() => _act(
    PlaybackCapability.shuffle,
    'toggleShuffle',
    _local.toggleShuffle,
    _cast.toggleShuffle,
  );

  Future<void> cycleRepeat() => _act(
    PlaybackCapability.repeat,
    'cycleRepeat',
    _local.cycleRepeat,
    () async {
      throw const PlaybackActionUnavailable(
        'Repeat is not available on Chromecast.',
      );
    },
  );

  /// Explicit transfer to local playback for Jellyfin-addressed commands.
  ///
  /// When Cast owns playback, awaits `disconnect(resumeLocal: false)`, which
  /// restores the edited Cast queue paused before the local action runs and
  /// never autoplays. Failures propagate so a failed Cast stop prevents the
  /// local action. No-op while already local.
  Future<void> stopCastingForLocalTransfer() async {
    if (_cast.ownership == CastOwnership.local) return;
    await _cast.disconnect(resumeLocal: false);
  }

  /// Explicit transfer to local playback.
  ///
  /// Delegates to a successful Cast disconnect/resume; the displayed
  /// destination changes only once restoration finishes. No-op while
  /// already local; frozen while a handoff is transferring.
  Future<void> resumeHere() async {
    switch (_cast.ownership) {
      case CastOwnership.local:
        return;
      case CastOwnership.transferring:
        throw const PlaybackActionUnavailable(
          'resumeHere is not available right now.',
        );
      case CastOwnership.remote:
      case CastOwnership.recovering:
        _error = null;
        _inflight++;
        _rebuild();
        try {
          await _cast.disconnect(resumeLocal: true);
        } catch (error) {
          _error = error is PlaybackActionUnavailable
              ? error.message
              : redactSecrets(error);
          _rebuild();
          rethrow;
        } finally {
          _inflight--;
          _rebuild();
        }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _local.removeListener(_rebuild);
    _positionSub.cancel();
    _volumeSub.cancel();
    _cast.removeListener(_rebuild);
    _castPositionSub.cancel();
    super.dispose();
  }
}
