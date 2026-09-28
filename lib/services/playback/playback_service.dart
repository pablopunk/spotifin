import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:audio_session/audio_session.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../platform/playback_state_store.dart';
import '../../storage/database.dart';
import '../downloads/download_service.dart';
import '../jellyfin/jellyfin_client.dart';
import '../jellyfin/session.dart';
import 'mobile_queue.dart';
import 'playback_history.dart';
import 'playback_snapshot.dart';
import 'queue_item_identity.dart';
import 'queue_state.dart';
import 'remote_playback.dart';

/// Occurrence id key inside [MediaItem] extras.
///
/// [MediaItem.id] stays the track id; the occurrence id addresses one queue
/// entry so duplicate tracks and stale player events resolve unambiguously.
const String kOccurrenceIdKey = 'occurrenceId';

/// Source revision key inside [MediaItem] extras.
///
/// The revision increments on every committed audio source installation.
/// Events whose tags carry an older revision are obsolete and ignored.
const String kSourceRevisionKey = 'sourceRevision';

/// Prior audio snapshot used to roll back a failed audio change.
class _AudioSnapshot {
  _AudioSnapshot({
    required this.session,
    required this.entries,
    required this.index,
    required this.position,
    required this.playing,
    required this.revision,
  });

  final JellyfinSession session;
  final List<QueueEntry> entries;
  final int index;
  final Duration position;
  final bool playing;

  /// Source revision the snapshot's tags were built with.
  final int revision;
}

class PlaybackService extends ChangeNotifier implements RemotePlayback {
  PlaybackService(
    this._client,
    this._downloads, {
    AudioPlayer? player,
    PlaybackStateStore? stateStore,
    Future<void> Function()? configureAudioSession,
    math.Random? random,
  }) : _player = player ?? AudioPlayer(),
       _stateStore = stateStore ?? PlaybackStateStore(),
       _configureAudioSession =
           configureAudioSession ?? _defaultConfigureAudioSession,
       _random = random ?? math.Random() {
    _subscriptions.add(
      _player.playerStateStream.listen((playerState) {
        if (playerState.processingState == ProcessingState.completed) {
          unawaited(
            _enqueue((generation) => _finishCompletedQueueNow(generation)),
          );
        } else {
          unawaited(_reportProgress());
        }
        notifyListeners();
      }),
    );
    _subscriptions.add(
      _player.currentIndexStream.listen((index) {
        _onIndexEvent(index);
      }),
    );
    _subscriptions.add(
      _player.positionStream.listen((position) {
        final second = position.inSeconds;
        if (second != _lastSavedSecond) {
          _lastSavedSecond = second;
          _persistPosition(position);
        }
        if (second % 10 == 0) {
          unawaited(_reportProgress());
        }
      }),
    );
    _subscriptions.add(
      _player.shuffleModeEnabledStream.listen((enabled) {
        if (enabled) unawaited(_player.setShuffleModeEnabled(false));
      }),
    );
  }

  final JellyfinClient _client;
  final DownloadService _downloads;
  final PlaybackStateStore _stateStore;
  final AudioPlayer _player;
  final Future<void> Function() _configureAudioSession;
  final QueueItemIdentity _queueItemIdentity = QueueItemIdentity();
  final StreamController<double> _volumeController =
      StreamController<double>.broadcast();
  final List<StreamSubscription<Object?>> _subscriptions = [];

  /// Ordered network report lane (Jellyfin playback reports only).
  Future<void> _reportQueue = Future.value();

  /// One private operation chain ordering every queue edit, replacement,
  /// restore, takeover, shuffle, extension, navigation, completion, and
  /// clear. Public methods enqueue exactly once; private implementations
  /// call each other directly and never await another chain task.
  Future<void> _operations = Future.value();

  /// Serialized local persistence lane (state-store writes only).
  Future<void> _persistence = Future.value();

  final Map<String, Track> _tracksById = {};
  final PlaybackHistory _history = PlaybackHistory();

  /// Single owner of queue entry identity, collection context, loaded
  /// window, current index, and the shuffle flag.
  QueueState _state = QueueState.empty();

  /// Account generation invalidating older work. [clear] and account changes
  /// bump it synchronously, before waiting for the chain; queued operations
  /// capture it and drop stale commits, saves, and reports.
  int _accountGeneration = 0;

  /// Audio source revision tagging installed [MediaItem] extras. Incremented
  /// only on committed source installations; stale tagged events are ignored.
  int _sourceRevision = 0;

  /// True while a chain task applies audio work. Index/completion events in
  /// this window must not publish intermediate state; the committing task
  /// reconciles the actual active source once afterwards.
  bool _audioInstalling = false;

  /// Last occurrence for which a transition was committed or processed.
  /// Repeat events for it are already-processed duplicates.
  String? _lastProcessedOccurrenceId;

  JellyfinSession? _session;
  bool _smallStreaming = false;
  bool _normalization = false;
  double _userVolume = 1;
  double _normalizationMultiplier = 1;
  LoopMode _loopMode = LoopMode.off;
  String? _reportedTrackId;
  String? _reportedOccurrenceId;
  String? _playSessionId;
  int _lastReportedSecond = -1;
  int _lastSavedSecond = -1;
  bool _castingActive = false;
  final math.Random _random;

  static const _queueExtensionThreshold = 15;

  AudioPlayer get player => _player;
  double get volume => _userVolume;
  Stream<double> get volumeStream => _volumeController.stream;

  /// Currently loaded queue tracks.
  List<Track> get queue => _state.loadedTracks;

  /// Whether a Chromecast receiver currently owns playback.
  ///
  /// While true, local Jellyfin progress/playing reports are suppressed so
  /// the receiver is the single reporting session. The local queue, history,
  /// and saved position are left intact for resume on disconnect.
  bool get isCastingActive => _castingActive;

  void setCastingActive(bool active) {
    _castingActive = active;
  }

  /// Tracks played this session since the last server confirmation.
  ///
  /// Transient overlay only: the History UI merges this on top of Jellyfin's
  /// Recently Played truth (see `mergeRecentlyPlayed`). Never persisted;
  /// Jellyfin remains the only durable history store via the playback reports
  /// this service already sends.
  List<Track> get history => _history.items;

  /// Visible queue: current track first, then remaining upcoming tracks.
  ///
  /// The underlying loaded queue is unchanged. Played entries before
  /// [currentIndex] are hidden here; use [history] to go back to them.
  List<Track> get upcomingQueue =>
      MobileQueueView.upcoming(queue, currentIndex);

  /// Full-queue index backing `upcomingQueue[0]`.
  int get upcomingOffset =>
      MobileQueueView.offsetFor(currentIndex, queue.length);
  bool get playing => _player.playing;
  bool get shuffle => _state.shuffle;
  LoopMode get loopMode => _loopMode;

  /// Window-relative index of the current entry in the committed state.
  int? get currentIndex => _state.currentIndex;

  Track? get currentTrack {
    final tag = _player.sequenceState.currentSource?.tag;
    if (tag is MediaItem) {
      final occurrenceId = tag.extras?[kOccurrenceIdKey] as String?;
      if (occurrenceId != null) {
        final match = _findLoadedByOccurrence(occurrenceId);
        if (match != null) return match.track;
      }
    }
    return _state.currentEntry?.track;
  }

  Future<void> configure(
    JellyfinSession session, {
    bool smallStreaming = false,
    bool normalization = false,
  }) {
    final previous = _session;
    if (previous == null || _accountId(session) != _accountId(previous)) {
      _accountGeneration++;
    }
    _session = session;
    _smallStreaming = smallStreaming;
    _normalization = normalization;
    return _enqueue((generation) async {
      await _configureAudioSession();
      if (generation != _accountGeneration) return;
      final track = currentTrack;
      if (track != null) await _applyGain(track);
    });
  }

  static Future<void> _defaultConfigureAudioSession() async {
    final audioSession = await AudioSession.instance;
    await audioSession.configure(const AudioSessionConfiguration.music());
  }

  Future<void> replaceQueue(
    List<Track> tracks, {
    int? startIndex,
    bool? shuffle,
  }) => _enqueue(
    (generation) => _replaceQueueNow(
      tracks,
      startIndex: startIndex,
      shuffle: shuffle,
      generation: generation,
      autoplay: true,
    ),
  );

  Future<void> _replaceQueueNow(
    List<Track> tracks, {
    int? startIndex,
    bool? shuffle,
    required int generation,
    required bool autoplay,
  }) async {
    final session = _session;
    if (tracks.isEmpty || session == null) return;
    final candidate = QueueState.prepare(
      tracks,
      startIndex: startIndex,
      shuffle: shuffle ?? _state.shuffle,
      random: _random,
      newId: _newPlaylistItemId,
    );
    await _installCollection(
      candidate: candidate,
      session: session,
      generation: generation,
      initialPosition: Duration.zero,
      autoplay: autoplay,
    );
  }

  Future<void> playTrack(Track track, List<Track> context) =>
      _enqueue((generation) async {
        final index = context.indexWhere((item) => item.id == track.id);
        await _replaceQueueNow(
          context,
          startIndex: index < 0 ? 0 : index,
          generation: generation,
          autoplay: true,
        );
      });

  @override
  Future<void> addToQueue(Track track) =>
      _enqueue((generation) => _addToQueueNow(track, generation));

  Future<void> _addToQueueNow(Track track, int generation) async {
    final session = _session;
    if (session == null) return;
    final candidate = _state.append(track, newId: _newPlaylistItemId);
    final prior = _capturePriorAudio(session);
    try {
      await _guardedAudio(() async {
        await _player.addAudioSource(
          (await _sources(session, [
            candidate.entries.last,
          ], prior.revision)).single,
        );
      });
    } catch (error) {
      await _recoverPriorAudio(prior);
      rethrow;
    }
    if (generation != _accountGeneration) return;
    _commitState(candidate, generation: generation);
    _rememberTracks([track]);
    await _persistCommittedState(generation);
    unawaited(_reportProgress(force: true));
    notifyListeners();
  }

  @override
  Future<void> addNextToQueue(List<Track> tracks) =>
      _enqueue((generation) => _insertNextNow(tracks, generation));

  Future<void> _insertNextNow(List<Track> tracks, int generation) async {
    final session = _session;
    if (session == null || tracks.isEmpty) return;
    final base = _state;
    final candidate = base.insertNext(tracks, newId: _newPlaylistItemId);
    // The audio list mirrors the loaded window, so translation is
    // window-relative; the collapsed candidate starts at zero.
    final insertAt = (base.currentIndex ?? -1) + 1;
    final added = candidate.entries.sublist(insertAt, insertAt + tracks.length);
    final prior = _capturePriorAudio(session);
    try {
      await _guardedAudio(() async {
        await _player.insertAudioSources(
          insertAt,
          await _sources(session, added, prior.revision),
        );
      });
    } catch (error) {
      await _recoverPriorAudio(prior);
      rethrow;
    }
    if (generation != _accountGeneration) return;
    _commitState(candidate, generation: generation);
    _rememberTracks(tracks);
    await _persistCommittedState(generation);
    unawaited(_reportProgress(force: true));
    notifyListeners();
  }

  Future<void> removeAt(int index) =>
      _enqueue((generation) => _removeAtNow(index, generation));

  Future<void> _removeAtNow(int index, int generation) async {
    final session = _session;
    if (session == null) return;
    final candidate = _state.removeAt(index);
    if (identical(candidate, _state)) return;
    final prior = _capturePriorAudio(session);
    try {
      await _guardedAudio(() => _player.removeAudioSourceAt(index));
    } catch (error) {
      await _recoverPriorAudio(prior);
      rethrow;
    }
    if (generation != _accountGeneration) return;
    _commitState(candidate, generation: generation);
    await _persistCommittedState(generation);
    unawaited(_reportProgress(force: true));
    notifyListeners();
  }

  Future<void> removeTrack(String trackId) =>
      _enqueue((generation) => _removeTrackNow(trackId, generation));

  Future<void> _removeTrackNow(String trackId, int generation) async {
    final session = _session;
    if (session == null) return;
    final base = _state;
    final candidate = base.removeTrack(trackId);
    if (identical(candidate, _state)) return;
    final prior = _capturePriorAudio(session);
    try {
      await _guardedAudio(() async {
        final loaded = base.loadedEntries;
        for (var index = loaded.length - 1; index >= 0; index--) {
          if (loaded[index].track.id != trackId) continue;
          await _player.removeAudioSourceAt(index);
        }
      });
    } catch (error) {
      await _recoverPriorAudio(prior);
      rethrow;
    }
    if (generation != _accountGeneration) return;
    _commitState(candidate, generation: generation);
    _tracksById.remove(trackId);
    _history.removeTrack(trackId);
    await _persistCommittedState(generation);
    unawaited(_reportProgress(force: true));
    notifyListeners();
  }

  Future<void> reorder(int oldIndex, int newIndex) =>
      _enqueue((generation) => _reorderNow(oldIndex, newIndex, generation));

  Future<void> _reorderNow(int oldIndex, int newIndex, int generation) async {
    final session = _session;
    if (session == null) return;
    final candidate = _state.reorder(oldIndex, newIndex);
    if (identical(candidate, _state)) return;
    final prior = _capturePriorAudio(session);
    try {
      await _guardedAudio(() => _player.moveAudioSource(oldIndex, newIndex));
    } catch (error) {
      await _recoverPriorAudio(prior);
      rethrow;
    }
    if (generation != _accountGeneration) return;
    _commitState(candidate, generation: generation);
    await _persistCommittedState(generation);
    unawaited(_reportProgress(force: true));
    notifyListeners();
  }

  /// Plays a track chosen from the History list.
  ///
  /// Takes the [Track] itself (not an index) because the visible History list
  /// is Jellyfin's Recently Played merged with the session overlay, not the
  /// overlay alone. Preserves the previous history-tap behavior: the track is
  /// queued next and playback jumps to it, leaving the rest of the queue
  /// intact.
  Future<void> playHistoryTrack(Track track) =>
      _enqueue((generation) => _playHistoryTrackNow(track, generation));

  Future<void> _playHistoryTrackNow(Track track, int generation) async {
    if (_session == null) return;
    _rememberTracks([track]);
    await _insertNextNow([track], generation);
    if (generation != _accountGeneration) return;
    final target = (_state.currentIndex ?? -1) + 1;
    await _playQueueIndexNow(target, generation);
  }

  /// Plays a mobile (upcoming-view) index.
  ///
  /// Mobile index 0 is the current track; translation keeps desktop's
  /// full-queue indices untouched.
  Future<void> playUpcomingIndex(int mobileIndex) => _enqueue((generation) {
    final full = MobileQueueView.toFullIndex(
      mobileIndex,
      _state.currentIndex,
      _state.loadedEntries.length,
    );
    if (full < 0) return Future.value();
    return _playQueueIndexNow(full, generation);
  });

  /// Removes a mobile (upcoming-view) index.
  Future<void> removeUpcomingAt(int mobileIndex) => _enqueue((generation) {
    final full = MobileQueueView.toFullIndex(
      mobileIndex,
      _state.currentIndex,
      _state.loadedEntries.length,
    );
    if (full < 0) return Future.value();
    return _removeAtNow(full, generation);
  });

  /// Reorders within the mobile (upcoming-view) list.
  ///
  /// The current track stays pinned at mobile index 0: moves involving it
  /// are ignored so the mobile queue always keeps current first and only
  /// the remaining upcoming order changes.
  Future<void> reorderUpcoming(int oldMobileIndex, int newMobileIndex) =>
      _enqueue((generation) {
        final translated = MobileQueueView.reorderFullIndices(
          oldMobileIndex,
          newMobileIndex,
          _state.currentIndex,
          _state.loadedEntries.length,
        );
        if (translated == null) return Future.value();
        return _reorderNow(translated.$1, translated.$2, generation);
      });

  @override
  Future<void> toggle() => _enqueue((generation) async {
    if (_player.playing) {
      await _savePosition(_player.position, generation);
      await _pauseNow(generation);
      return;
    }
    await _playNow(generation);
  });

  @override
  Future<void> pause() => _enqueue(_pauseNow);

  Future<void> _pauseNow(int generation) async {
    if (!_player.playing) return;
    await _guardedAudio(() => _player.pause());
    if (generation != _accountGeneration) return;
    unawaited(_reportProgress(force: true));
  }

  @override
  Future<void> play() => _enqueue(_playNow);

  Future<void> _playNow(int generation) async {
    if (_player.playing) return;
    // Never await AudioPlayer.play(): its future can represent the whole
    // playback session rather than the request itself.
    unawaited(_player.play());
    if (generation != _accountGeneration) return;
    unawaited(_reportProgress(force: true));
  }

  @override
  Future<void> stop() => _enqueue((generation) async {
    _scheduleStopReport();
    await _guardedAudio(() => _player.stop());
    if (generation != _accountGeneration) return;
    notifyListeners();
  });

  @override
  Future<void> next() => _enqueue((generation) => _nextNow(generation));

  Future<void> _nextNow(int generation) async {
    final state = _state;
    final index = state.currentIndex;
    if (index == null || state.loadedEntries.isEmpty) return;
    final next = index + 1;
    if (next >= state.loadedEntries.length) {
      // Queue exhaustion (or loop wrap handled by the player): keep the
      // previous just_audio behavior without manufacturing history.
      await _guardedAudio(() => _player.seekToNext());
      return;
    }
    final outgoing = state.loadedEntries[index];
    final target = state.loadedEntries[next];
    await _guardedAudio(() => _player.seekToNext());
    if (generation != _accountGeneration) return;
    _history.record(outgoing.track);
    final candidate = state.selectEntry(target.id);
    _commitState(candidate, generation: generation);
    _lastProcessedOccurrenceId = target.id;
    _schedulePlayingReport(target);
    unawaited(_persistCommittedState(generation));
    unawaited(_extendQueueIfNeeded());
    notifyListeners();
  }

  Future<void> playQueueIndex(int index) =>
      _enqueue((generation) => _playQueueIndexNow(index, generation));

  Future<void> _playQueueIndexNow(int index, int generation) async {
    final state = _state;
    if (index < 0 || index >= state.loadedEntries.length) return;
    final current = state.currentIndex;
    final target = state.loadedEntries[index];
    if (current != null && index == current) {
      await _guardedAudio(() => _player.seek(Duration.zero, index: index));
      if (generation != _accountGeneration) return;
      _lastProcessedOccurrenceId = target.id;
      _schedulePlayingReport(target);
      // Never await AudioPlayer.play().
      unawaited(_player.play());
      unawaited(_reportProgress(force: true));
      return;
    }
    if (current != null && index > current) {
      // Forward jump: the track being left was played.
      if (current >= 0 && current < state.loadedEntries.length) {
        _history.record(state.loadedEntries[current].track);
      }
    } else {
      // Backward jump: the target (and newer history) becomes
      // current/upcoming again, so unwind history instead of pushing.
      // Direction-first keeps duplicate track ids correct: a forward jump
      // onto a duplicate id still records, a backward jump never pushes.
      if (_history.containsId(target.track.id)) {
        _history.removeUpToId(target.track.id);
      }
    }
    await _guardedAudio(() => _player.seek(Duration.zero, index: index));
    if (generation != _accountGeneration) return;
    final candidate = state.selectEntry(target.id);
    _commitState(candidate, generation: generation);
    _lastProcessedOccurrenceId = target.id;
    _schedulePlayingReport(target);
    // Never await AudioPlayer.play().
    unawaited(_player.play());
    unawaited(_reportProgress(force: true));
    await _persistCommittedState(generation);
    unawaited(_extendQueueIfNeeded());
    notifyListeners();
  }

  @override
  Future<void> previous() => _enqueue((generation) => _previousNow(generation));

  Future<void> _previousNow(int generation) async {
    final state = _state;
    if (state.loadedEntries.isEmpty) return;
    if (_player.position > const Duration(seconds: 4)) {
      await _guardedAudio(() => _player.seek(Duration.zero));
      if (generation != _accountGeneration) return;
      unawaited(_reportProgress(force: true));
      return;
    }
    if (_history.isEmpty) {
      // No recorded history: preserve the old seekToPrevious fallback but
      // suppress the automatic history push so the upcoming list and
      // history stay distinct.
      final index = state.currentIndex;
      await _guardedAudio(() => _player.seekToPrevious());
      if (generation != _accountGeneration) return;
      if (index != null && index - 1 >= 0) {
        final candidate = state.selectEntry(state.loadedEntries[index - 1].id);
        _commitState(candidate, generation: generation);
        final entry = candidate.currentEntry;
        _lastProcessedOccurrenceId = entry?.id;
        if (entry != null) _schedulePlayingReport(entry);
      }
      return;
    }
    final target = _history.mostRecent;
    if (target == null) {
      await _guardedAudio(() => _player.seekToPrevious());
      return;
    }
    final found =
        _findInQueueBeforeCurrent(target.id) ??
        state.loadedTracks.indexWhere((item) => item.id == target.id);
    if (found < 0) {
      // History entry is no longer queued: drop it instead of stalling,
      // then fall back to the player behavior.
      _history.takeFirst();
      await _persistCommittedState(generation);
      notifyListeners();
      await _guardedAudio(() => _player.seekToPrevious());
      return;
    }
    final entry = state.loadedEntries[found];
    _history.takeFirst();
    await _guardedAudio(() => _player.seek(Duration.zero, index: found));
    if (generation != _accountGeneration) return;
    final candidate = state.selectEntry(entry.id);
    _commitState(candidate, generation: generation);
    _lastProcessedOccurrenceId = entry.id;
    _schedulePlayingReport(entry);
    // Never await AudioPlayer.play().
    unawaited(_player.play());
    unawaited(_reportProgress(force: true));
    await _persistCommittedState(generation);
    notifyListeners();
  }

  int? _findInQueueBeforeCurrent(String trackId) {
    final current = _state.currentIndex;
    if (current == null) return null;
    final loaded = _state.loadedEntries;
    for (var i = current - 1; i >= 0; i--) {
      if (loaded[i].track.id == trackId) return i;
    }
    return null;
  }

  /// Enqueues [task] on the single operation chain.
  ///
  /// The task is skipped when a [clear] or account change invalidated its
  /// captured generation before it starts. The chain itself never breaks:
  /// task errors reach the caller while the lane stays alive for the next
  /// operation, so an operation after a prior failure still runs.
  Future<void> _enqueue(Future<void> Function(int generation) task) {
    final generation = _accountGeneration;
    final result = _operations.then((_) {
      if (generation != _accountGeneration) return Future<void>.value();
      return task(generation);
    });
    _operations = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  @override
  Future<void> seek(Duration position) => _enqueue((generation) async {
    await _guardedAudio(() => _player.seek(position));
    if (generation != _accountGeneration) return;
    await _savePosition(position, generation);
    unawaited(_reportProgress(force: true));
  });

  @override
  Future<void> setVolume(double volume) async {
    _userVolume = volume.clamp(0.0, 1.0);
    _volumeController.add(_userVolume);
    await _updateOutputVolume();
    unawaited(_reportProgress(force: true));
  }

  Future<void> toggleShuffle() =>
      _enqueue((generation) => _toggleShuffleNow(generation));

  Future<void> _toggleShuffleNow(int generation) async {
    final session = _session;
    if (session == null) return;
    if (_state.shuffle) {
      final marked = _state.withShuffle(false);
      _commitState(marked, generation: generation);
      await _persistCommittedState(generation);
      unawaited(_reportProgress(force: true));
      notifyListeners();
      return;
    }
    final state = _state;
    final index = state.currentIndex;
    if (index == null || state.loadedEntries.isEmpty) {
      final marked = state.withShuffle(true);
      _commitState(marked, generation: generation);
      await _persistCommittedState(generation);
      unawaited(_reportProgress(force: true));
      notifyListeners();
      return;
    }
    // One candidate through the single commit path: the shuffle flag and
    // the shuffled order publish together only on successful audio work.
    final candidate = state.withShuffle(true).shuffleRemaining(random: _random);
    await _installCollection(
      candidate: candidate,
      session: session,
      generation: generation,
      initialPosition: _player.position,
      autoplay: _player.playing,
    );
  }

  Future<void> cycleRepeat() => _enqueue((generation) async {
    _loopMode = switch (_loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await _guardedAudio(() => _player.setLoopMode(_loopMode));
    if (generation != _accountGeneration) return;
    unawaited(_reportProgress(force: true));
    notifyListeners();
  });

  @override
  Future<void> setShuffle(bool enabled) => _enqueue((generation) async {
    if (_state.shuffle == enabled) return;
    await _toggleShuffleNow(generation);
  });

  @override
  Future<void> setRepeatMode(LoopMode mode) => _enqueue((generation) async {
    if (_loopMode == mode) return;
    _loopMode = mode;
    await _guardedAudio(() => _player.setLoopMode(mode));
    if (generation != _accountGeneration) return;
    unawaited(_reportProgress(force: true));
    notifyListeners();
  });

  @override
  Future<void> takeOver(
    List<Track> tracks, {
    required int startIndex,
    required Duration position,
  }) => _enqueue(
    (generation) => _takeOverNow(
      tracks,
      startIndex: startIndex,
      position: position,
      generation: generation,
    ),
  );

  Future<void> _takeOverNow(
    List<Track> tracks, {
    required int startIndex,
    required Duration position,
    required int generation,
  }) async {
    final session = _session;
    if (tracks.isEmpty || session == null) return;
    final candidate = QueueState.restore(
      tracks,
      index: startIndex.clamp(0, tracks.length - 1),
      shuffle: _state.shuffle,
      newId: _newPlaylistItemId,
    );
    final selected = candidate.loadedTracks[candidate.currentIndex ?? 0];
    final duration = Duration(microseconds: selected.durationTicks ~/ 10);
    final safePosition = position > duration ? duration : position;
    await _installCollection(
      candidate: candidate,
      session: session,
      generation: generation,
      initialPosition: safePosition,
      autoplay: true,
    );
  }

  Future<void> restore(List<Track> catalog) =>
      _enqueue((generation) => _restoreNow(catalog, generation));

  Future<void> _restoreNow(List<Track> catalog, int generation) async {
    final session = _session;
    if (session == null || catalog.isEmpty) return;
    final encoded = await _stateStore.read(_accountId(session));
    if (generation != _accountGeneration) return;
    if (encoded == null) return;
    final snapshot = jsonDecode(encoded) as Map<String, dynamic>;
    final ids = (snapshot['queue'] as List<dynamic>? ?? const [])
        .cast<String>();
    final byId = {for (final track in catalog) track.id: track};
    final tracks = ids.map((id) => byId[id]).whereType<Track>().toList();
    if (tracks.isEmpty) return;
    // Older snapshots may contain a persisted 'history' list from when the
    // app maintained its own duplicate history. It is intentionally ignored:
    // Jellyfin is the durable history store and the session overlay starts
    // empty on every launch.
    final candidate = QueueState.restore(
      tracks,
      index: (snapshot['index'] as int? ?? 0),
      shuffle: snapshot['shuffle'] as bool? ?? false,
      newId: _newPlaylistItemId,
    );
    final milliseconds = snapshot['positionMilliseconds'] as int? ?? 0;
    await _installCollection(
      candidate: candidate,
      session: session,
      generation: generation,
      initialPosition: Duration(milliseconds: milliseconds),
      autoplay: false,
    );
    if (generation != _accountGeneration) return;
    await _player.pause();
    await _savePosition(_player.position, generation);
  }

  Future<void> clear() {
    // Invalidate older work immediately, before waiting for the chain, so
    // in-flight operations cannot publish or report into the cleared state.
    _accountGeneration++;
    final generation = _accountGeneration;
    return _enqueue((_) => _clearNow(generation));
  }

  /// Captures an atomic local snapshot for Cast handoff and recovery.
  ///
  /// The queue state carries the full collection context (including any
  /// unloaded tail) with every occurrence id retained; history is captured
  /// without persisting it.
  PlaybackSnapshot captureSnapshot() => PlaybackSnapshot(
    queue: _state,
    position: _player.position,
    playing: _player.playing,
    repeatMode: _loopMode,
    history: _history.items,
  );

  /// Restores a snapshot atomically through the operation chain.
  ///
  /// Occurrence ids are retained (no new ids are allocated) and no `play()`
  /// is issued when the snapshot is paused. Report suppression is left
  /// untouched: callers release it and report the restored state afterwards.
  Future<void> restoreSnapshot(PlaybackSnapshot snapshot) =>
      _enqueue((generation) => _restoreSnapshotNow(snapshot, generation));

  Future<void> _restoreSnapshotNow(
    PlaybackSnapshot snapshot,
    int generation,
  ) async {
    final session = _session;
    if (session == null || snapshot.queue.loadedEntries.isEmpty) return;
    await _installCollection(
      candidate: snapshot.queue,
      session: session,
      generation: generation,
      initialPosition: snapshot.position,
      autoplay: snapshot.playing,
    );
    if (generation != _accountGeneration) return;
    if (_loopMode != snapshot.repeatMode) {
      _loopMode = snapshot.repeatMode;
      await _guardedAudio(() => _player.setLoopMode(_loopMode));
      if (generation != _accountGeneration) return;
    }
    _history
      ..clear()
      ..load(snapshot.history);
    await _persistCommittedState(generation);
    notifyListeners();
  }

  /// Reports the currently committed state immediately.
  ///
  /// Used after Cast handoff cleanup releases report suppression so the
  /// restored local state is reported exactly once on the serialized path.
  Future<void> reportCurrentState() =>
      _enqueue((generation) async {
        if (generation != _accountGeneration) return;
        final entry = _state.currentEntry;
        if (entry == null) return;
        _schedulePlayingOnly(entry);
        await _persistCommittedState(generation);
      });

  Future<void> _clearNow(int generation) async {
    final session = _session;
    final accountKey = session == null ? null : _accountId(session);
    _scheduleStopReport();
    try {
      await _player.stop();
    } catch (_) {}
    _state = QueueState.empty();
    _history.clear();
    _tracksById.clear();
    _lastProcessedOccurrenceId = null;
    _reportedTrackId = null;
    _reportedOccurrenceId = null;
    _playSessionId = null;
    _loopMode = LoopMode.off;
    _session = null;
    // Drain in-flight position writes first: they carry the older generation
    // and drop, so no late write can recreate state after this clear.
    await _persistence;
    if (accountKey != null) {
      await _stateStore.clear(accountKey);
    }
    if (generation != _accountGeneration) return;
    notifyListeners();
  }

  /// Installs [candidate]'s loaded window as the live audio sources.
  ///
  /// Builds the candidate sources, applies them, and only then publishes the
  /// candidate: history, persistence, and reports all follow a successful
  /// commit. When audio work fails after partially changing native state,
  /// the prior audio snapshot and position are reloaded; when recovery also
  /// fails, audio stops while the prior logical queue is retained, and the
  /// original failure is surfaced without publishing success.
  Future<void> _installCollection({
    required QueueState candidate,
    required JellyfinSession session,
    required int generation,
    required Duration initialPosition,
    required bool autoplay,
  }) async {
    final prior = _capturePriorAudio(session);
    final revision = _sourceRevision + 1;
    try {
      await _guardedAudio(
        () => _installSources(
          entries: candidate.loadedEntries,
          initialIndex: candidate.currentIndex ?? 0,
          initialPosition: initialPosition,
          revision: revision,
        ),
      );
    } catch (error) {
      await _recoverPriorAudio(prior);
      rethrow;
    }
    if (generation != _accountGeneration) return;
    _sourceRevision = revision;
    _commitState(candidate, generation: generation);
    _rememberTracks(candidate.collectionTracks);
    await _reconcileActiveSource(generation);
    // Never await AudioPlayer.play().
    if (autoplay) unawaited(_player.play());
    unawaited(_reportProgress(force: true));
  }

  Future<void> _installSources({
    required List<QueueEntry> entries,
    required int initialIndex,
    required Duration initialPosition,
    required int revision,
  }) async {
    final session = _session!;
    await _player.stop();
    await _player.clearAudioSources();
    await _player.setAudioSources(
      await _sources(session, entries, revision),
      initialIndex: initialIndex,
      initialPosition: initialPosition,
    );
    await _player.setShuffleModeEnabled(false);
    await _player.seek(initialPosition, index: initialIndex);
  }

  /// Captures the prior audio snapshot before an audio change.
  _AudioSnapshot _capturePriorAudio(JellyfinSession session) {
    final state = _state;
    return _AudioSnapshot(
      session: session,
      entries: List.of(state.loadedEntries),
      index: state.currentIndex ?? 0,
      position: _player.position,
      playing: _player.playing,
      revision: _sourceRevision,
    );
  }

  /// Reloads the prior audio snapshot after a failed change and rethrows the
  /// original [error]. When recovery also fails, audio stops while the prior
  /// logical queue is retained.
  Future<void> _recoverPriorAudio(_AudioSnapshot prior, {Object? error}) async {
    try {
      final revision = _sourceRevision + 1;
      await _player.stop();
      await _player.clearAudioSources();
      await _player.setAudioSources(
        await _sources(prior.session, prior.entries, revision),
        initialIndex: prior.index,
        initialPosition: prior.position,
      );
      await _player.setShuffleModeEnabled(false);
      await _player.seek(prior.position, index: prior.index);
      _sourceRevision = revision;
      // Never await AudioPlayer.play().
      if (prior.playing) unawaited(_player.play());
    } catch (_) {
      try {
        await _player.stop();
      } catch (_) {}
    }
    if (error != null) throw error;
  }

  /// Runs [work] while index/completion events are held back from publishing
  /// intermediate state. The committing task reconciles once afterwards.
  Future<T> _guardedAudio<T>(Future<T> Function() work) async {
    _audioInstalling = true;
    try {
      return await work();
    } finally {
      _audioInstalling = false;
    }
  }

  /// Publishes [candidate] as the committed state.
  void _commitState(QueueState candidate, {required int generation}) {
    _state = candidate;
  }

  QueueEntry? _findLoadedByOccurrence(String occurrenceId) {
    for (final entry in _state.loadedEntries) {
      if (entry.id == occurrenceId) return entry;
    }
    return null;
  }

  void _onIndexEvent(int? index) {
    if (_audioInstalling) return;
    final generation = _accountGeneration;
    unawaited(_enqueue((_) => _handleIndexEvent(index, generation)));
  }

  /// Handles one committed index transition exactly once.
  ///
  /// The event's occurrence, revision, and index are validated against the
  /// committed state and the current source. Obsolete revision events,
  /// already-processed occurrence transitions, and stale echoes for an index
  /// the player has already left are ignored.
  Future<void> _handleIndexEvent(int? eventIndex, int generation) async {
    if (generation != _accountGeneration) return;
    final resolved = _resolveEventOccurrence(eventIndex);
    if (resolved == null) return;
    if (resolved.id == _lastProcessedOccurrenceId) return;
    _recordHistory();
    await _finalizeTransition(resolved, generation);
  }

  QueueEntry? _resolveEventOccurrence(int? eventIndex) {
    final loaded = _state.loadedEntries;
    if (loaded.isEmpty) return null;
    final tag = _player.sequenceState.currentSource?.tag;
    if (tag is MediaItem) {
      final revision = tag.extras?[kSourceRevisionKey];
      if (revision is int && revision != _sourceRevision) return null;
      final occurrenceId = tag.extras?[kOccurrenceIdKey] as String?;
      if (occurrenceId != null) {
        return _findLoadedByOccurrence(occurrenceId);
      }
    }
    if (eventIndex == null) return null;
    // A player echo for an index that is no longer active is stale.
    if (eventIndex != _player.currentIndex) return null;
    if (eventIndex < 0 || eventIndex >= loaded.length) return null;
    return loaded[eventIndex];
  }

  Future<void> _finalizeTransition(QueueEntry entry, int generation) async {
    if (generation != _accountGeneration) return;
    final candidate = _state.selectEntry(entry.id);
    if (!identical(candidate, _state)) {
      _commitState(candidate, generation: generation);
    }
    _lastProcessedOccurrenceId = entry.id;
    unawaited(_extendQueueIfNeeded());
    await _applyGain(entry.track);
    _schedulePlayingReport(entry);
    await _persistCommittedState(generation);
    notifyListeners();
  }

  /// Reconciles the actual active source once after a committed install.
  Future<void> _reconcileActiveSource(int generation) async {
    if (generation != _accountGeneration) return;
    final loaded = _state.loadedEntries;
    if (loaded.isEmpty) return;
    QueueEntry? active;
    final tag = _player.sequenceState.currentSource?.tag;
    if (tag is MediaItem) {
      final occurrenceId = tag.extras?[kOccurrenceIdKey] as String?;
      if (occurrenceId != null) {
        active = _findLoadedByOccurrence(occurrenceId);
      }
    }
    final playerIndex = _player.currentIndex;
    if (active == null &&
        playerIndex != null &&
        playerIndex >= 0 &&
        playerIndex < loaded.length) {
      active = loaded[playerIndex];
    }
    active ??= _state.currentEntry;
    if (active == null) return;
    await _finalizeTransition(active, generation);
  }

  Future<void> _extendQueueIfNeeded() =>
      _enqueue((generation) => _extendNow(generation));

  Future<void> _extendNow(int generation) async {
    final session = _session;
    final state = _state;
    final index = state.currentIndex;
    if (session == null ||
        index == null ||
        !state.hasUnloadedTail ||
        state.loadedEntries.length - index > _queueExtensionThreshold) {
      return;
    }
    final candidate = state.extend();
    final added = candidate.loadedEntries.sublist(
      state.windowEnd - state.windowStart,
    );
    if (added.isEmpty) return;
    final revision = _sourceRevision;
    await _guardedAudio(() async {
      await _player.addAudioSources(await _sources(session, added, revision));
    });
    if (generation != _accountGeneration) return;
    _commitState(candidate, generation: generation);
    await _persistCommittedState(generation);
    notifyListeners();
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
    final loaded = _state.loadedEntries;
    final albumQueue =
        loaded.isNotEmpty &&
        loaded.every(
          (item) =>
              item.track.albumId != null && item.track.albumId == track.albumId,
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

  Future<List<AudioSource>> _sources(
    JellyfinSession session,
    List<QueueEntry> entries,
    int revision,
  ) async {
    final local = await _downloads.resolveAll(
      entries.map((entry) => entry.track.id),
    );
    return entries
        .map(
          (entry) => _source(session, entry, revision, local[entry.track.id]),
        )
        .toList(growable: false);
  }

  AudioSource _source(
    JellyfinSession session,
    QueueEntry entry,
    int revision, [
    Uri? local,
  ]) {
    final track = entry.track;
    return AudioSource.uri(
      local ?? _client.streamUri(session, track.id, small: _smallStreaming),
      tag: MediaItem(
        id: track.id,
        title: track.name,
        artist: track.artist,
        album: track.album,
        duration: Duration(microseconds: track.durationTicks ~/ 10),
        artUri: _client.imageUri(session, track.albumId ?? track.id),
        extras: {kOccurrenceIdKey: entry.id, kSourceRevisionKey: revision},
      ),
    );
  }

  String _encodeState(QueueState state, Duration position) => jsonEncode({
    'queue': [for (final entry in state.loadedEntries) entry.track.id],
    'index': state.currentIndex ?? 0,
    'positionMilliseconds': position.inMilliseconds,
    'shuffle': state.shuffle,
  });

  Future<void> _persistCommittedState(int generation) =>
      _persistSnapshot(_state, _player.position, generation);

  Future<void> _savePosition(Duration position, int generation) =>
      _persistSnapshot(_state, position, generation);

  Future<void> _persistSnapshot(
    QueueState state,
    Duration position,
    int generation,
  ) {
    final session = _session;
    if (session == null || state.loadedEntries.isEmpty) {
      return Future.value();
    }
    final accountKey = _accountId(session);
    final encoded = _encodeState(state, position);
    final result = _persistence.then((_) {
      if (generation != _accountGeneration) return Future<void>.value();
      return _stateStore.write(accountKey, encoded);
    });
    _persistence = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  /// Saves the current position from outside the operation chain (player
  /// position events). The write is serialized with the producing operation
  /// and dropped when a [clear] or account change invalidated its
  /// generation, so no late write recreates state after [clear].
  void _persistPosition(Duration position) {
    final generation = _accountGeneration;
    final session = _session;
    final state = _state;
    if (session == null || state.loadedEntries.isEmpty) return;
    final accountKey = _accountId(session);
    final encoded = _encodeState(state, position);
    final result = _persistence.then((_) {
      if (generation != _accountGeneration) return Future<void>.value();
      return _stateStore.write(accountKey, encoded);
    });
    _persistence = result.then<void>((_) {}, onError: (_, _) {});
  }

  String _accountId(JellyfinSession session) =>
      '${session.serverId}.${session.userId}';

  Future<void> _reportProgress({bool force = false}) {
    final generation = _accountGeneration;
    final session = _session;
    final trackId = _reportedTrackId;
    final occurrenceId = _reportedOccurrenceId;
    final playSessionId = _playSessionId;
    if (session == null || trackId == null || playSessionId == null) {
      return Future.value();
    }
    final accountKey = _accountId(session);
    final second = _player.position.inSeconds;
    if (!force && second == _lastReportedSecond) {
      return Future.value();
    }
    final position = _player.position;
    final playing = _player.playing;
    final volume = (_userVolume * 100).round();
    final repeatMode = _reportedRepeatMode;
    final shuffle = _state.shuffle;
    final currentOccurrenceId = occurrenceId;
    final queue = _reportedQueue;
    return _serializeReport(() async {
      if (generation != _accountGeneration) return;
      final current = _session;
      if (current == null || _accountId(current) != accountKey) return;
      // While a Chromecast receiver owns playback, the receiver reports as
      // its own Jellyfin session; the phone stays silent to avoid double
      // sessions.
      if (_castingActive) return;
      if (playSessionId != _playSessionId) return;
      if (occurrenceId != _reportedOccurrenceId) return;
      if (!force && second == _lastReportedSecond) return;
      _lastReportedSecond = second;
      try {
        await _client.reportPlayback(
          current,
          '/Sessions/Playing/Progress',
          trackId,
          position,
          playSessionId: playSessionId,
          paused: !playing,
          playlistItemId: currentOccurrenceId,
          queue: queue,
          volume: volume,
          repeatMode: repeatMode,
          shuffle: shuffle,
        );
      } catch (_) {}
    });
  }

  void _schedulePlayingReport(QueueEntry entry) {
    _scheduleStopReport();
    _schedulePlayingOnly(entry);
  }

  void _schedulePlayingOnly(QueueEntry entry) {
    final generation = _accountGeneration;
    final session = _session;
    if (session == null) return;
    final accountKey = _accountId(session);
    _reportedTrackId = entry.track.id;
    _reportedOccurrenceId = entry.id;
    final playSessionId =
        '${DateTime.now().microsecondsSinceEpoch}-${entry.track.id}';
    _playSessionId = playSessionId;
    _lastReportedSecond = -1;
    final position = _player.position;
    final playing = _player.playing;
    final volume = (_userVolume * 100).round();
    final repeatMode = _reportedRepeatMode;
    final shuffle = _state.shuffle;
    final queue = _reportedQueue;
    unawaited(
      _serializeReport(() async {
        if (generation != _accountGeneration) return;
        final current = _session;
        if (current == null || _accountId(current) != accountKey) return;
        if (_castingActive) return;
        if (playSessionId != _playSessionId) return;
        try {
          await _client.reportPlayback(
            current,
            '/Sessions/Playing',
            entry.track.id,
            position,
            playSessionId: playSessionId,
            paused: !playing,
            playlistItemId: entry.id,
            queue: queue,
            volume: volume,
            repeatMode: repeatMode,
            shuffle: shuffle,
          );
        } catch (_) {}
      }),
    );
  }

  void _scheduleStopReport() {
    final generation = _accountGeneration;
    final session = _session;
    final trackId = _reportedTrackId;
    final playSessionId = _playSessionId;
    _reportedTrackId = null;
    _reportedOccurrenceId = null;
    _playSessionId = null;
    if (session == null || trackId == null || playSessionId == null) return;
    final accountKey = _accountId(session);
    final position = _player.position;
    unawaited(
      _serializeReport(() async {
        if (generation != _accountGeneration) return;
        final current = _session;
        // The final stopped report for the outgoing owner is still
        // delivered in order, even while a receiver owns playback; only a
        // stale account drops it.
        if (current == null || _accountId(current) != accountKey) return;
        try {
          await _client.reportPlayback(
            current,
            '/Sessions/Playing/Stopped',
            trackId,
            position,
            playSessionId: playSessionId,
          );
        } catch (_) {}
      }),
    );
  }

  List<Map<String, String>> get _reportedQueue => [
    for (final entry in _state.loadedEntries)
      {'Id': entry.track.id, 'PlaylistItemId': entry.id},
  ];

  String get _reportedRepeatMode => switch (_loopMode) {
    LoopMode.off => 'RepeatNone',
    LoopMode.all => 'RepeatAll',
    LoopMode.one => 'RepeatOne',
  };

  String _newPlaylistItemId() => _queueItemIdentity.next();

  /// Records the outgoing track in the transient session overlay.
  ///
  /// Durable history is recorded by Jellyfin itself from the
  /// `/Sessions/Playing*` reports this service sends; this overlay only
  /// covers plays made since the last sync so the UI stays instant offline.
  void _recordHistory() {
    final previousId = _reportedTrackId;
    if (previousId == null) return;
    final previous = _tracksById[previousId];
    if (previous == null) return;
    _history.record(previous);
  }

  Future<void> _finishCompletedQueueNow(int generation) async {
    if (generation != _accountGeneration) return;
    _recordHistory();
    _scheduleStopReport();
    await _guardedAudio(() => _player.stop());
    if (generation != _accountGeneration) return;
    await _persistCommittedState(generation);
    notifyListeners();
  }

  Future<void> _serializeReport(Future<void> Function() report) {
    final result = _reportQueue.then((_) => report());
    _reportQueue = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }

  @override
  void dispose() {
    _accountGeneration++;
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _volumeController.close();
    _player.dispose();
    super.dispose();
  }
}
