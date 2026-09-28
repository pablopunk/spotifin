import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../storage/database.dart';
import '../jellyfin/session.dart';
import '../playback/playback_snapshot.dart';
import '../playback/queue_state.dart';
import '../redaction.dart';
import 'cast_device.dart';
import 'cast_playback_source.dart';
import 'cast_sender.dart';
import 'jellyfin_cast_adapter.dart';

/// Who owns playback right now.
///
/// Local is selected until a Cast handoff is pending ([transferring]) or
/// Cast owns ([remote]) or is awaiting the user's recovery decision
/// ([recovering]) after connection loss or a failed local restoration.
/// A disconnected transport alone never selects local: only a successful
/// restoration or account cleanup does. Discovery alone never changes it.
enum CastOwnership { local, transferring, remote, recovering }

/// Orchestrates the iPhone Chromecast MVP.
///
/// Flow: discover → connect → hand off the current track (title/artist/
/// album/artwork/duration/position) to the Jellyfin Web Receiver → drive
/// play/pause/seek/volume/next/previous remotely → disconnect restores the
/// retained Cast snapshot locally at the remote position. The local
/// queue/history is never mutated while casting: a snapshot is taken at
/// handoff and only used to resolve next/previous and to resume afterwards.
///
/// Failure handling is explicit and user-visible via [error]: sign-in
/// required, server unreachable by Cast (plain HTTP/localhost), nothing to
/// cast, unsupported platform, target disappearance, failed handoff (with a
/// one-time AAC fallback retry, restoring local on persistent failure),
/// connection loss (recovery ownership: retry or resume locally), and
/// background/foreground transitions (discovery paused/resumed).
class CastController extends ChangeNotifier {
  CastController({
    required CastPlaybackSource playback,
    required JellyfinCastAdapter adapter,
    required CastSender sender,
    bool Function()? isSupported,
    math.Random? random,
    // ignore: prefer_initializing_formals
  }) : _playback = playback,
       // ignore: prefer_initializing_formals
       _adapter = adapter,
       // ignore: prefer_initializing_formals
       _sender = sender,
       // ignore: prefer_initializing_formals
       _isSupported = isSupported ?? (() => isCastPlatformSupported),
       _random = random ?? math.Random();

  final CastPlaybackSource _playback;
  final JellyfinCastAdapter _adapter;
  final CastSender _sender;
  final bool Function() _isSupported;
  final math.Random _random;
  int _castIds = 0;

  static const _queueExtensionThreshold = 15;

  JellyfinSession? _session;
  bool _unstableReceiver = false;
  bool _initialized = false;
  bool _initializing = false;
  bool _disposed = false;

  /// Ordered command lane replacing the old silent busy-call loss. Public
  /// methods enqueue exactly once; private implementations call each other
  /// directly and never await another lane task.
  Future<void> _commands = Future.value();

  /// Lifecycle generation invalidating in-flight handoff/retry/restore work.
  /// [configure], account replacement, and disposal bump it synchronously;
  /// queued commands capture it and old completions cannot set casting true,
  /// resume audio, or publish an old account's snapshot.
  int _generation = 0;

  CastOwnership _ownership = CastOwnership.local;

  List<CastDevice> _devices = const [];
  CastConnectionState _connection = CastConnectionState.disconnected;
  CastDevice? _connectedDevice;
  CastRemoteState _remote = const CastRemoteState();

  /// Last usable media position/playing decision, kept separately from the
  /// transport display [_remote]. Unknown/empty transport-reset events never
  /// overwrite it, and buffering never flips a playing decision to paused,
  /// so retry and local resume keep working after a disconnect reset.
  Duration _recoveryPosition = Duration.zero;
  bool _recoveryPlaying = false;

  /// Complete Cast snapshot retained for resume (whole edited queue state).
  PlaybackSnapshot? _castSnapshot;

  /// Local snapshot captured at handoff, used to restore local playback
  /// when a handoff fails.
  PlaybackSnapshot? _localSnapshot;

  CastDevice? _lastDevice;

  /// True while a command intentionally ends the sender session, so the
  /// resulting transport disconnect does not trigger recovery ownership.
  bool _leavingRemote = false;

  String? _error;

  StreamSubscription<List<CastDevice>>? _devicesSub;
  StreamSubscription<CastConnectionState>? _connectionSub;
  StreamSubscription<CastRemoteState>? _remoteSub;

  bool get initialized => _initialized;
  bool get initializing => _initializing;

  /// Whether a Cast command is queued or running. Commands are ordered on
  /// the lane instead of dropped; widgets use this only to disable controls
  /// while work is in flight.
  bool get busy => _inflight > 0;
  int _inflight = 0;

  /// Current playback owner. Notified on every change.
  CastOwnership get ownership => _ownership;

  /// Whether a receiver owns playback or awaits the recovery decision.
  /// Derived from [ownership] so loss retains the Cast destination.
  bool get isCasting =>
      _ownership == CastOwnership.remote ||
      _ownership == CastOwnership.recovering;

  bool get isSupported => _isSupported();
  bool get useUnstableReceiver => _unstableReceiver;

  List<CastDevice> get devices => _devices;
  CastConnectionState get connectionState => _connection;
  CastDevice? get connectedDevice => _connectedDevice;
  String? get connectedDeviceName => _connectedDevice?.friendlyName;
  CastRemoteState get remoteState => _remote;

  /// Currently loaded Cast entry, derived from the shared queue state.
  Track? get remoteTrack => _castSnapshot?.queue.currentEntry?.track;

  /// Window-relative index of the current Cast entry.
  int get remoteIndex => _castSnapshot?.queue.currentIndex ?? 0;

  /// Loaded Cast queue tracks. The local queue is never mutated while
  /// casting; remote selection and edits resolve against this list.
  List<Track> get castQueue => List.unmodifiable([
    for (final entry in _castSnapshot?.queue.loadedEntries ?? const [])
      entry.track,
  ]);
  Duration get remotePosition => _remote.position;
  Duration? get remoteDuration {
    if (_remote.duration != null) return _remote.duration;
    final track = remoteTrack;
    if (track == null) return null;
    return Duration(microseconds: track.durationTicks ~/ 10);
  }

  bool get remotePlaying => _remote.isPlaying;
  double get remoteVolume => _remote.volume;

  /// Position updates mirrored from the receiver (drives sliders).
  Stream<Duration> get positionStream =>
      _sender.remoteStateStream.map((state) => state.position);
  String? get error => _error;
  JellyfinSession? get session => _session;

  /// Whether a handoff can be attempted right now (UI enablement).
  bool get canCast {
    if (!_isSupported() || _session == null) return false;
    if (_playback.currentTrack == null) return false;
    final blocker = _serverBlocker();
    return blocker == null;
  }

  /// User-visible reason casting is unavailable, if any.
  String? get unavailableReason {
    if (!_isSupported()) {
      return 'Chromecast is available on iPhone and Android.';
    }
    if (_session == null) return 'Sign in to cast to Chromecast.';
    if (_playback.currentTrack == null) return 'Nothing playing to cast.';
    return _serverBlocker();
  }

  String? _serverBlocker() {
    final session = _session;
    if (session == null) return null;
    final uri = Uri.tryParse(session.serverUrl);
    if (uri == null) return 'This Jellyfin server address is invalid.';
    return JellyfinCastAdapter.serverBlockerMessage(uri);
  }

  Future<void> initialize() => _enqueue((generation) => _initializeNow());

  Future<void> _initializeNow() async {
    if (_initialized || _initializing) return;
    _initializing = true;
    _safeNotify();
    try {
      await _sender.initialize(
        receiverAppId: JellyfinCastAdapter.receiverAppId(
          unstable: _unstableReceiver,
        ),
      );
      _devicesSub ??= _sender.devicesStream.listen((devices) {
        _devices = devices;
        // Target disappearance while connected: the session stream drives
        // the disconnect; here we surface it when the picker is open.
        if (_connectedDevice != null &&
            _connection == CastConnectionState.connected &&
            devices.isNotEmpty &&
            !devices.any((d) => d.id == _connectedDevice!.id)) {
          _fail(
            '${_connectedDevice!.friendlyName} is no longer available. '
            'Reconnect or resume on this iPhone.',
          );
        }
        _safeNotify();
      });
      _connectionSub ??= _sender.connectionStateStream.listen(_onConnection);
      _remoteSub ??= _sender.remoteStateStream.listen(_onRemote);
      _devices = _sender.devices;
      _connection = _sender.connectionState;
      _connectedDevice = _sender.connectedDevice;
      _remote = _sender.remoteState;
      await _sender.startDiscovery();
      _initialized = true;
      _error = null;
    } on CastException catch (error) {
      _error = error.message;
    } catch (error) {
      _error = redactSecrets(error);
    } finally {
      _initializing = false;
      _safeNotify();
    }
  }

  /// Configures the account session, returning an awaitable cleanup future.
  ///
  /// Invalidation is synchronous: an account change (including sign-out)
  /// immediately defeats in-flight handoff/retry/restore work. Unchanged-
  /// account configuration never ends Cast or resets its queue.
  Future<void> configure(JellyfinSession? session) {
    final previous = _session;
    _session = session;
    if (_accountKey(session) == _accountKey(previous)) {
      return Future.value();
    }
    _generation++;
    final generation = _generation;
    return _enqueue((_) => _cleanupNow(generation));
  }

  Future<void> _cleanupNow(int generation) async {
    if (_ownership == CastOwnership.local &&
        _castSnapshot == null &&
        _localSnapshot == null &&
        _sender.connectionState == CastConnectionState.disconnected) {
      _safeNotify();
      return;
    }
    _leavingRemote = true;
    try {
      await _sender.disconnect(stopReceiver: true);
    } catch (_) {
      // Account teardown is best-effort on the receiver; the local
      // transition below still runs so no stale snapshot can revive.
    } finally {
      _leavingRemote = false;
    }
    if (generation != _generation) return;
    _connection = CastConnectionState.disconnected;
    _connectedDevice = null;
    _castSnapshot = null;
    _localSnapshot = null;
    _playback.setCastingActive(false);
    _setOwnership(CastOwnership.local);
    _safeNotify();
  }

  Future<void> setReceiverChannel(bool unstable) => _enqueue((_) async {
    if (_unstableReceiver == unstable) return;
    _unstableReceiver = unstable;
    _initialized = false;
    await _initializeNow();
  });

  void _onConnection(CastConnectionState state) {
    _connection = state;
    _connectedDevice = _sender.connectedDevice;
    if (state == CastConnectionState.disconnected) {
      _connectedDevice = null;
      if (_ownership == CastOwnership.remote && !_leavingRemote) {
        // Unexpected disconnect retains Cast ownership in recovery mode;
        // it never starts local audio without the user's resume action.
        _setOwnership(CastOwnership.recovering);
        // Reconnect, target disappearance, or failed handoff path: keep the
        // snapshot + last usable position so retry/resume can proceed, and
        // surface explicit guidance instead of silently dropping.
        _fail(
          'Chromecast connection lost. Reconnect to resume where you left '
          'off, or resume on this iPhone.',
        );
      }
    }
    _safeNotify();
  }

  void _onRemote(CastRemoteState state) {
    _remote = state;
    _adoptRecovery(state);
    _safeNotify();
  }

  /// Keeps the last usable position/playing decision apart from transport
  /// display resets. Unknown/empty resets never overwrite it; buffering
  /// never flips a playing decision; legitimate zero-position seeks and
  /// paused updates remain valid.
  void _adoptRecovery(CastRemoteState state) {
    switch (state.playerState) {
      case CastPlayerState.unknown:
        return;
      case CastPlayerState.idle:
        if (state.position == Duration.zero && state.duration == null) return;
        _recoveryPosition = state.position;
        _recoveryPlaying = false;
      case CastPlayerState.buffering:
        _recoveryPosition = state.position;
      case CastPlayerState.playing:
        _recoveryPosition = state.position;
        _recoveryPlaying = true;
      case CastPlayerState.paused:
        _recoveryPosition = state.position;
        _recoveryPlaying = false;
    }
  }

  Future<void> connect(CastDevice device) =>
      _enqueue((generation) => _connectNow(device, generation));

  Future<void> _connectNow(CastDevice device, int generation) async {
    _error = null;
    _safeNotify();
    if (!_isSupported()) {
      throw const CastException(
        'Chromecast is available on iPhone and Android.',
      );
    }
    await _initializeNow();
    if (generation != _generation) return;
    await _sender.connect(device);
    await _waitForConnection();
    if (generation != _generation) return;
    _connection = _sender.connectionState;
    _connectedDevice = _sender.connectedDevice ?? device;
    _lastDevice = device;
    _safeNotify();
    // Auto-handoff keeps the iPhone MVP to one tap: picking a target hands
    // off the current track at its current position. Calls the direct core:
    // ordinary queueing would serialize behind this connect.
    if (_playback.currentTrack != null && _ownership == CastOwnership.local) {
      await _castCurrentNow(generation);
    }
  }

  Future<void> _waitForConnection() async {
    if (_sender.connectionState == CastConnectionState.connected) return;
    try {
      await _sender.connectionStateStream
          .firstWhere((state) => state == CastConnectionState.connected)
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const CastException('Chromecast did not finish connecting.');
    }
  }

  /// Hands the current track to Chromecast at the current position.
  ///
  /// Preserves queue/history: the local queue is snapshotted (not mutated)
  /// and local audio is stopped (phone session → Stopped) with further local
  /// reports suppressed until disconnect.
  Future<void> castCurrent() =>
      _enqueue((generation) => _castCurrentNow(generation));

  Future<void> _castCurrentNow(int generation) async {
    final session = _session;
    if (session == null) {
      throw const CastException('Sign in to cast to Chromecast.');
    }
    if (!_isSupported()) {
      throw const CastException(
        'Chromecast is available on iPhone and Android.',
      );
    }
    final blocker = _serverBlocker();
    if (blocker != null) throw CastException(blocker);
    final track = _playback.currentTrack;
    if (track == null) throw const CastException('Nothing playing to cast.');
    if (_connection != CastConnectionState.connected &&
        _connectedDevice == null) {
      throw const CastException('Connect to a Chromecast first.');
    }
    final localSnapshot = _playback.captureSnapshot();
    final position = _playback.position;

    _setOwnership(CastOwnership.transferring);
    // The outgoing local stopped report goes out on the serialized path
    // before receiver ownership begins.
    await _playback.stopForCast();
    _playback.setCastingActive(true);
    try {
      await _loadWithFallback(
        session,
        track,
        position,
        playlistItemId: localSnapshot.queue.currentEntry?.id,
        autoplay: true,
      );
    } catch (error) {
      await _abortHandoff(localSnapshot, generation);
      rethrow;
    }
    if (generation != _generation) return;
    _localSnapshot = null;
    // Retain the complete local snapshot (full collection context,
    // occurrence ids, repeat, and temporary history) for later resume.
    _castSnapshot = localSnapshot.copyWith(position: position, playing: true);
    _recoveryPosition = position;
    _recoveryPlaying = true;
    _setOwnership(CastOwnership.remote);
    _error = null;
    _safeNotify();
  }

  /// Aborts a failed handoff: stops any receiver item that might have
  /// started, then restores the captured local snapshot. When receiver
  /// shutdown cannot be confirmed, recovery ownership is retained and local
  /// audio stays stopped; a failed receiver stop never starts local audio
  /// or releases suppression.
  Future<void> _abortHandoff(
    PlaybackSnapshot localSnapshot,
    int generation,
  ) async {
    try {
      await _sender.stop();
    } catch (_) {
      _setOwnership(CastOwnership.recovering);
      _castSnapshot = localSnapshot;
      return;
    }
    if (generation != _generation) return;
    try {
      await _playback.restoreSnapshot(localSnapshot);
    } catch (_) {
      _setOwnership(CastOwnership.recovering);
      _castSnapshot = localSnapshot;
      rethrow;
    }
    _playback.setCastingActive(false);
    _setOwnership(CastOwnership.local);
    await _playback.reportCurrentState();
  }

  Future<void> _loadWithFallback(
    JellyfinSession session,
    Track track,
    Duration position, {
    String? playlistItemId,
    required bool autoplay,
  }) async {
    try {
      final payload = _adapter.buildPayload(
        session,
        track,
        position: position,
        playlistItemId: playlistItemId,
      );
      await _sender.loadSingle(
        payload,
        position: payload.startPosition,
        autoplay: autoplay,
      );
      _remote = _remote.copyWith(
        position: payload.startPosition,
        duration: payload.duration,
        playerState: autoplay
            ? CastPlayerState.playing
            : CastPlayerState.paused,
      );
      return;
    } on CastException {
      // Fall through to the AAC retry below.
    }
    // Receiver rejected the original container (or the first attempt hit a
    // transient load error): retry once with the AAC/m4a profile before
    // surfacing a failure, mirroring the local `small` streaming fallback.
    try {
      final fallback = _adapter.buildPayload(
        session,
        track,
        position: position,
        playlistItemId: playlistItemId,
        small: true,
      );
      await _sender.loadSingle(
        fallback,
        position: fallback.startPosition,
        autoplay: autoplay,
      );
      _remote = _remote.copyWith(
        position: fallback.startPosition,
        duration: fallback.duration,
        playerState: autoplay
            ? CastPlayerState.playing
            : CastPlayerState.paused,
      );
      return;
    } on CastException catch (error) {
      throw CastException(
        error.message.isEmpty
            ? 'This track can\u2019t play on Chromecast.'
            : error.message,
      );
    }
  }

  Future<void> play() => _castGuarded(() => _sender.play());
  Future<void> pause() => _castGuarded(() => _sender.pause());

  Future<void> toggle() => _castGuarded(() async {
    if (_remote.isPlaying) {
      await _sender.pause();
    } else {
      await _sender.play();
    }
  });

  Future<void> seek(Duration position) => _castGuarded(() async {
    final duration = remoteDuration;
    final safe = position.isNegative
        ? Duration.zero
        : (duration != null && position > duration ? duration : position);
    await _sender.seek(safe);
    _recoveryPosition = safe;
  });

  Future<void> setVolume(double volume) =>
      _castGuarded(() => _sender.setVolume(volume.clamp(0.0, 1.0)));

  Future<void> next() => _remoteGuarded((generation) async {
    final snapshot = _castSnapshot;
    if (snapshot == null) {
      throw const CastException('Nothing is casting right now.');
    }
    var queue = snapshot.queue;
    if (queue.loadedEntries.isEmpty) {
      await _sender.next();
      return;
    }
    // Extend the queue model near the tail before resolving the next entry.
    if (queue.hasUnloadedTail &&
        queue.currentIndex != null &&
        queue.loadedEntries.length - queue.currentIndex! <=
            _queueExtensionThreshold) {
      queue = queue.extend();
      _castSnapshot = snapshot.copyWith(queue: queue);
    }
    final at = (queue.currentIndex ?? -1) + 1;
    if (at >= queue.loadedEntries.length) {
      throw const CastException('You\u2019re at the end of the queue.');
    }
    await _selectRemoteEntry(
      candidate: queue,
      targetIndex: at,
      position: Duration.zero,
      autoplay: true,
      generation: generation,
    );
  });

  Future<void> previous() => _remoteGuarded((generation) async {
    // Mirror local behavior: restart the track when well into it.
    if (_remote.position > const Duration(seconds: 4)) {
      await _sender.seek(Duration.zero);
      _recoveryPosition = Duration.zero;
      return;
    }
    final snapshot = _castSnapshot;
    if (snapshot == null) {
      throw const CastException('Nothing is casting right now.');
    }
    final queue = snapshot.queue;
    if (queue.loadedEntries.isEmpty) {
      await _sender.previous();
      return;
    }
    final at = (queue.currentIndex ?? 0) - 1;
    if (at < 0) {
      await _sender.seek(Duration.zero);
      _recoveryPosition = Duration.zero;
      return;
    }
    await _selectRemoteEntry(
      candidate: queue,
      targetIndex: at,
      position: Duration.zero,
      autoplay: true,
      generation: generation,
    );
  });

  /// Jumps the receiver to a snapshot index (queue taps while casting).
  Future<void> playIndex(int index) => _remoteGuarded((generation) async {
    final snapshot = _castSnapshot;
    if (snapshot == null) {
      throw const CastException('Nothing is casting right now.');
    }
    final queue = snapshot.queue;
    if (queue.loadedEntries.isEmpty) {
      throw const CastException('Nothing is casting.');
    }
    final at = index.clamp(0, queue.loadedEntries.length - 1);
    if (at == queue.currentIndex) {
      await _sender.seek(Duration.zero);
      _recoveryPosition = Duration.zero;
      return;
    }
    await _selectRemoteEntry(
      candidate: queue,
      targetIndex: at,
      position: Duration.zero,
      autoplay: true,
      generation: generation,
    );
  });

  /// Cast queue edits and selection, matching local method names and
  /// argument meanings. Pure edits commit without a receiver load; changing
  /// the current entry loads it. Local audio remains stopped throughout.
  Future<void> replaceQueue(
    List<Track> tracks, {
    int? startIndex,
    bool? shuffle,
  }) => _remoteGuarded(
    (generation) => _replaceQueueNow(
      tracks,
      startIndex: startIndex,
      shuffle: shuffle,
      generation: generation,
    ),
  );

  Future<void> _replaceQueueNow(
    List<Track> tracks, {
    int? startIndex,
    bool? shuffle,
    required int generation,
  }) async {
    final session = _session;
    final snapshot = _castSnapshot;
    if (session == null || snapshot == null) {
      throw const CastException('Nothing is casting right now.');
    }
    if (tracks.isEmpty) return;
    final candidate = QueueState.prepare(
      tracks,
      startIndex: startIndex,
      shuffle: shuffle ?? snapshot.queue.shuffle,
      random: _random,
      newId: _newCastId,
    );
    await _selectRemoteEntry(
      candidate: candidate,
      targetIndex: candidate.currentIndex ?? 0,
      position: Duration.zero,
      autoplay: true,
      generation: generation,
    );
  }

  Future<void> playTrack(Track track, List<Track> context) =>
      _remoteGuarded((generation) async {
        final index = context.indexWhere((item) => item.id == track.id);
        await _replaceQueueNow(
          context,
          startIndex: index < 0 ? 0 : index,
          generation: generation,
        );
      });

  Future<void> addToQueue(Track track) => _remoteGuarded((_) async {
    final snapshot = _castSnapshot;
    if (snapshot == null) {
      throw const CastException('Nothing is casting right now.');
    }
    _commitCastQueue(snapshot.queue.append(track, newId: _newCastId));
  });

  Future<void> addNextToQueue(List<Track> tracks) => _remoteGuarded((_) async {
    final snapshot = _castSnapshot;
    if (snapshot == null) {
      throw const CastException('Nothing is casting right now.');
    }
    if (tracks.isEmpty) return;
    _commitCastQueue(snapshot.queue.insertNext(tracks, newId: _newCastId));
  });

  Future<void> removeAt(int index) =>
      _remoteGuarded((generation) => _removeAtNow(index, generation));

  Future<void> _removeAtNow(int index, int generation) async {
    final snapshot = _castSnapshot;
    if (snapshot == null) {
      throw const CastException('Nothing is casting right now.');
    }
    final queue = snapshot.queue;
    if (index < 0 || index >= queue.loadedEntries.length) return;
    final removed = queue.loadedEntries[index];
    final candidate = queue.removeAt(index);
    await _commitRemoval(
      candidate: candidate,
      removedCurrent: removed.id == queue.currentEntry?.id,
      generation: generation,
    );
  }

  Future<void> removeTrack(String trackId) =>
      _remoteGuarded((generation) => _removeTrackNow(trackId, generation));

  Future<void> _removeTrackNow(String trackId, int generation) async {
    final snapshot = _castSnapshot;
    if (snapshot == null) {
      throw const CastException('Nothing is casting right now.');
    }
    final queue = snapshot.queue;
    final candidate = queue.removeTrack(trackId);
    if (identical(candidate, queue)) return;
    final before = queue.currentEntry?.id;
    final kept =
        before != null &&
        candidate.loadedEntries.any((entry) => entry.id == before);
    await _commitRemoval(
      candidate: candidate,
      removedCurrent: !kept,
      generation: generation,
    );
  }

  /// Commits a removal: pure edits keep the receiver untouched, removing the
  /// current entry loads its successor (or the new last entry) at zero while
  /// retaining playing/paused state, and removing the final entry stops the
  /// receiver, commits the empty queue, and retains the Cast connection.
  Future<void> _commitRemoval({
    required QueueState candidate,
    required bool removedCurrent,
    required int generation,
  }) async {
    if (!removedCurrent) {
      _commitCastQueue(candidate);
      return;
    }
    if (candidate.loadedEntries.isEmpty) {
      await _sender.stop();
      if (generation != _generation) return;
      final snapshot = _castSnapshot;
      if (snapshot == null) return;
      _castSnapshot = snapshot.copyWith(
        queue: candidate,
        position: Duration.zero,
        playing: false,
      );
      _recoveryPosition = Duration.zero;
      _recoveryPlaying = false;
      _safeNotify();
      return;
    }
    await _selectRemoteEntry(
      candidate: candidate,
      targetIndex: candidate.currentIndex ?? 0,
      position: Duration.zero,
      autoplay: _recoveryPlaying,
      generation: generation,
    );
  }

  Future<void> reorder(int oldIndex, int newIndex) => _remoteGuarded((_) async {
    final snapshot = _castSnapshot;
    if (snapshot == null) {
      throw const CastException('Nothing is casting right now.');
    }
    final candidate = snapshot.queue.reorder(oldIndex, newIndex);
    if (identical(candidate, snapshot.queue)) return;
    _commitCastQueue(candidate);
  });

  Future<void> playHistoryTrack(Track track) =>
      _remoteGuarded((generation) => _playHistoryTrackNow(track, generation));

  Future<void> _playHistoryTrackNow(Track track, int generation) async {
    final snapshot = _castSnapshot;
    if (snapshot == null) {
      throw const CastException('Nothing is casting right now.');
    }
    final current = snapshot.queue.currentEntry;
    final history = [
      if (current != null) current.track,
      ...snapshot.history,
    ].take(100).toList();
    final inserted = snapshot.queue.insertNext([track], newId: _newCastId);
    final target = (inserted.currentIndex ?? -1) + 1;
    await _selectRemoteEntry(
      candidate: inserted,
      targetIndex: target,
      position: Duration.zero,
      autoplay: true,
      history: history,
      generation: generation,
    );
  }

  Future<void> toggleShuffle() => _remoteGuarded((_) async {
    final snapshot = _castSnapshot;
    if (snapshot == null) {
      throw const CastException('Nothing is casting right now.');
    }
    final queue = snapshot.queue;
    // Shuffle preserves the current/past prefix and permutes future entries
    // using the shared queue model; the current audio never restarts.
    final candidate = queue.shuffle
        ? queue.withShuffle(false)
        : queue.withShuffle(true).shuffleRemaining(random: _random);
    _commitCastQueue(candidate);
  });

  /// Loads [candidate]'s entry at [targetIndex] on the receiver, then
  /// commits it as the authoritative recovery snapshot. Pure queue entries
  /// keep their occurrence ids, including duplicate tracks and payload
  /// playlist ids. A failed load retains the prior snapshot and attempts to
  /// restore the prior remote item and position; recovery failure surfaces
  /// without starting local audio.
  Future<void> _selectRemoteEntry({
    required QueueState candidate,
    required int targetIndex,
    required Duration position,
    required bool autoplay,
    List<Track>? history,
    required int generation,
  }) async {
    final session = _session;
    final prior = _castSnapshot;
    if (session == null || prior == null) {
      throw const CastException('Nothing is casting right now.');
    }
    final target = candidate.loadedEntries[targetIndex];
    try {
      await _loadWithFallback(
        session,
        target.track,
        position,
        playlistItemId: target.id,
        autoplay: autoplay,
      );
    } catch (error) {
      try {
        final current = prior.queue.currentEntry;
        if (current != null) {
          await _loadWithFallback(
            session,
            current.track,
            _recoveryPosition,
            playlistItemId: current.id,
            autoplay: _recoveryPlaying,
          );
        }
      } catch (_) {
        _setOwnership(CastOwnership.recovering);
      }
      rethrow;
    }
    if (generation != _generation) return;
    _castSnapshot = prior.copyWith(
      queue: candidate.selectEntry(target.id),
      position: position,
      playing: autoplay,
      history: history,
    );
    _recoveryPosition = position;
    _recoveryPlaying = autoplay;
    _safeNotify();
  }

  void _commitCastQueue(QueueState queue) {
    final snapshot = _castSnapshot;
    if (snapshot == null) return;
    _castSnapshot = snapshot.copyWith(queue: queue);
    _safeNotify();
  }

  String _newCastId() => 'cast-${_castIds++}';

  Future<void> _remoteGuarded(Future<void> Function(int generation) action) =>
      _enqueue((generation) async {
        if (_ownership != CastOwnership.remote) {
          if (_ownership == CastOwnership.local) {
            throw const CastException('Nothing is casting right now.');
          }
          throw const CastException(
            'Chromecast is changing state. Try again in a moment.',
          );
        }
        await action(generation);
      });

  /// Reconnects to the last target and reloads at the last usable position.
  ///
  /// The recovery decision is captured before the first await and passed as
  /// `autoplay` through both normal and AAC-fallback loads; load events
  /// never re-read a flag the load itself may change.
  Future<void> retry() => _enqueue((generation) => _retryNow(generation));

  Future<void> _retryNow(int generation) async {
    final device = _lastDevice;
    final session = _session;
    final entry = _castSnapshot?.queue.currentEntry;
    if (device == null || entry == null || session == null) {
      throw const CastException(
        'Nothing to reconnect. Pick a Chromecast and try again.',
      );
    }
    final position = _recoveryPosition;
    final autoplay = _recoveryPlaying;
    await _initializeNow();
    if (generation != _generation) return;
    await _sender.connect(device);
    await _waitForConnection();
    if (generation != _generation) return;
    _connection = _sender.connectionState;
    _connectedDevice = _sender.connectedDevice ?? device;
    await _loadWithFallback(
      session,
      entry.track,
      position,
      playlistItemId: entry.id,
      autoplay: autoplay,
    );
    if (generation != _generation) return;
    _setOwnership(CastOwnership.remote);
    _error = null;
    _safeNotify();
  }

  /// Ends the Cast session and resumes local playback where remote left off.
  ///
  /// Resume restores the complete retained Cast snapshot (not an index into
  /// whatever local queue happens to remain). `resumeLocal:false` with a
  /// valid account restores that snapshot paused; account invalidation
  /// discards the snapshot and never restores it. Receiver shutdown or
  /// local restoration failure retains recovery data and reports the Cast
  /// error without starting local audio.
  Future<void> disconnect({bool resumeLocal = true}) =>
      _enqueue((generation) => _disconnectNow(resumeLocal, generation));

  Future<void> _disconnectNow(bool resumeLocal, int generation) async {
    // Capture the recovery decision before the first await.
    final position = _recoveryPosition;
    final resumePlaying = resumeLocal && _recoveryPlaying;
    final snapshot = _castSnapshot;
    if (snapshot == null &&
        _ownership == CastOwnership.local &&
        _sender.connectionState == CastConnectionState.disconnected) {
      return;
    }
    _leavingRemote = true;
    try {
      await _sender.disconnect(stopReceiver: true);
    } catch (_) {
      _setOwnership(CastOwnership.recovering);
      rethrow;
    } finally {
      _leavingRemote = false;
    }
    if (generation != _generation) return;
    _connection = CastConnectionState.disconnected;
    _connectedDevice = null;
    if (_session == null || snapshot == null) {
      // Account invalidation discards the snapshot and never restores it.
      _castSnapshot = null;
      _localSnapshot = null;
      _playback.setCastingActive(false);
      _setOwnership(CastOwnership.local);
      _safeNotify();
      return;
    }
    // Local ownership is published only after restoration finishes.
    try {
      await _playback.restoreSnapshot(
        snapshot.copyWith(position: position, playing: resumePlaying),
      );
    } catch (_) {
      _setOwnership(CastOwnership.recovering);
      rethrow;
    }
    if (generation != _generation) return;
    _playback.setCastingActive(false);
    _setOwnership(CastOwnership.local);
    await _playback.reportCurrentState();
    _castSnapshot = null;
    _localSnapshot = null;
    _error = null;
    _safeNotify();
  }

  /// Restarts discovery after the app returns to the foreground.
  ///
  /// Sessions suspend (not end) when backgrounded so lockscreen controls keep
  /// working; on foreground we resume discovery and re-emit current state so
  /// position keeps mirroring the receiver.
  Future<void> handleAppForeground() async {
    if (!_initialized) return;
    try {
      await _sender.startDiscovery();
    } catch (_) {}
    _remote = _sender.remoteState;
    _connection = _sender.connectionState;
    _safeNotify();
  }

  /// Pauses discovery when backgrounded to save battery. The receiver keeps
  /// playing (`stopCastingOnAppTerminated=false`).
  Future<void> handleAppBackground() async {
    try {
      await _sender.stopDiscovery();
    } catch (_) {}
  }

  void clearError() {
    _error = null;
    _safeNotify();
  }

  Future<void> _castGuarded(Future<void> Function() action) =>
      _enqueue((_) async {
        if (!isCasting) {
          throw const CastException('Nothing is casting right now.');
        }
        await action();
      });

  /// Orders commands instead of silently dropping busy calls. Errors surface
  /// through [error] and the caller; stale generations return silently; the
  /// lane itself never breaks.
  Future<void> _enqueue(Future<void> Function(int generation) task) {
    if (_disposed) return Future.value();
    final generation = _generation;
    _inflight++;
    _safeNotify();
    final result = _commands
        .then((_) {
          if (generation != _generation || _disposed) {
            return Future<void>.value();
          }
          return task(generation);
        })
        .then(
          (_) {
            // Preserve the error value for the caller without breaking the lane.
          },
          onError: (Object error) {
            if (error is CastException) {
              _fail(error.message);
            } else {
              final message = redactSecrets(error);
              _fail(message);
              throw CastException(message);
            }
            throw error;
          },
        );
    _commands = result.then<void>((_) {}, onError: (_, _) {});
    return result.whenComplete(() {
      _inflight--;
      _safeNotify();
    });
  }

  void _setOwnership(CastOwnership ownership) {
    if (_ownership == ownership) return;
    _ownership = ownership;
    _safeNotify();
  }

  String? _accountKey(JellyfinSession? session) =>
      session == null ? null : '${session.serverId}.${session.userId}';

  void _fail(String message) {
    if (_disposed) return;
    _error = message.isEmpty ? 'Chromecast request failed.' : message;
    _safeNotify();
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    // Invalidate in-flight work so no later completion can notify or
    // publish; the borrowed sender and local playback stay alive for the
    // provider that owns them.
    _generation++;
    _disposed = true;
    _devicesSub?.cancel();
    _connectionSub?.cancel();
    _remoteSub?.cancel();
    super.dispose();
  }
}
