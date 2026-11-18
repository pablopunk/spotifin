import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../storage/database.dart';
import '../jellyfin/session.dart';
import '../playback/playback_snapshot.dart';
import '../playback/queue_state.dart';
import '../redaction.dart';
import 'cast_device.dart';
import 'cast_playback_source.dart';
import 'cast_sender.dart';
import 'jellyfin_cast_adapter.dart';
import 'jellyfin_receiver_protocol.dart';
import 'receiver_queue.dart';

/// Who owns playback right now.
///
/// Local is selected until a Cast handoff is pending ([transferring]) or
/// Cast owns ([remote]) or the Cast session dropped and the Cast SDK may
/// still resume it ([recovering]). A disconnected transport alone never selects local: only
/// a successful restoration or account cleanup does.
enum CastOwnership { local, transferring, remote, recovering }

/// Drives Chromecast playback the way Spotify Connect does: the receiver
/// owns the queue and the phone is a remote.
///
/// Handoff sends the queue (item ids, start index and position) to the
/// Jellyfin receiver with `PlayNow`. The receiver advances on its own when a
/// track ends and reports playback to the server, so music keeps going while
/// the phone sleeps. The phone keeps the desired queue ([PlaybackSnapshot])
/// and a [ReceiverQueue] mirror of what the receiver holds; it follows the
/// receiver's reported item id to know the current occurrence, appends with
/// `PlayLast`, and reloads the receiver at the same position only when an
/// edit changes the order of what is already there.
///
/// A dropped session (iOS suspends it in the background, Wi-Fi blips) is not
/// an error: the Cast SDK resumes it and the controller adopts whatever the
/// receiver is playing. The controller never relaunches the receiver on its
/// own, because a session ended from the TV, Google Home or another app must
/// stay ended: when no resume arrives within [sessionLossGrace] in the
/// foreground, playback returns to the phone, paused.
class CastController extends ChangeNotifier {
  CastController({
    required CastPlaybackSource playback,
    required CastSender sender,
    bool Function()? isSupported,
    math.Random? random,
    this.sessionLossGrace = const Duration(seconds: 20),
    this.resyncDelay = const Duration(milliseconds: 1200),
    this.adoptTimeout = const Duration(seconds: 4),
    // ignore: prefer_initializing_formals
  }) : _playback = playback,
       // ignore: prefer_initializing_formals
       _sender = sender,
       // ignore: prefer_initializing_formals
       _isSupported = isSupported ?? (() => isCastPlatformSupported),
       _random = random ?? math.Random();

  final CastPlaybackSource _playback;
  final CastSender _sender;
  final bool Function() _isSupported;
  final math.Random _random;

  /// How long a dropped session may take to resume in the foreground before
  /// it counts as ended.
  final Duration sessionLossGrace;

  /// Coalesces queue edits that reorder the receiver into one reload.
  final Duration resyncDelay;

  /// How long a rejoin waits for the receiver to report its media.
  final Duration adoptTimeout;

  int _castIds = 0;

  static const _queueExtensionThreshold = 15;
  static const _awaitTimeout = Duration(seconds: 20);

  JellyfinSession? _session;
  bool _unstableReceiver = false;
  bool _initialized = false;
  bool _initializing = false;
  bool _disposed = false;
  bool _foreground = true;

  /// Ordered command lane. Public methods enqueue exactly once; private
  /// implementations call each other directly and never await another lane
  /// task.
  Future<void> _commands = Future.value();

  /// Lifecycle generation invalidating in-flight work on account change and
  /// disposal.
  int _generation = 0;

  CastOwnership _ownership = CastOwnership.local;

  List<CastDevice> _devices = const [];
  CastConnectionState _connection = CastConnectionState.disconnected;
  CastDevice? _connectedDevice;
  CastRemoteState _remote = const CastRemoteState();

  /// Last usable media position/playing decision, kept apart from transport
  /// display resets so rejoin and local resume continue where Cast was.
  Duration _recoveryPosition = Duration.zero;
  bool _recoveryPlaying = false;

  /// Desired Cast queue (whole edited queue state), retained for resume.
  PlaybackSnapshot? _castSnapshot;

  /// What the receiver holds, in the order sent.
  ReceiverQueue? _receiver;

  /// Entry just requested from the receiver. Status for any other item is
  /// stale until the receiver reports this one.
  QueueEntry? _awaiting;
  DateTime? _awaitingSince;

  /// Entry to pause as soon as the receiver starts it (paused reloads).
  String? _pauseOnArrival;

  CastDevice? _lastDevice;

  /// True while a command intentionally ends the sender session, so the
  /// resulting transport disconnect does not start a rejoin.
  bool _leavingRemote = false;

  Timer? _resyncTimer;
  Timer? _sessionLossTimer;

  /// An edit reordered the receiver while paused; it reloads on play rather
  /// than audibly restarting now.
  bool _resyncOnPlay = false;

  /// A correction for a stale receiver advance is queued; further statuses
  /// must not queue another.
  bool _correcting = false;

  String? _error;

  StreamSubscription<List<CastDevice>>? _devicesSub;
  StreamSubscription<CastConnectionState>? _connectionSub;
  StreamSubscription<CastRemoteState>? _remoteSub;
  StreamSubscription<String>? _receiverMessagesSub;

  bool get initialized => _initialized;
  bool get initializing => _initializing;

  /// Whether a Cast command is queued or running.
  bool get busy => _inflight > 0;
  int _inflight = 0;

  CastOwnership get ownership => _ownership;

  bool get isCasting =>
      _ownership == CastOwnership.remote ||
      _ownership == CastOwnership.recovering;

  bool get isSupported => _isSupported();
  bool get useUnstableReceiver => _unstableReceiver;

  List<CastDevice> get devices => _devices;
  CastConnectionState get connectionState => _connection;
  CastDevice? get connectedDevice => _connectedDevice;
  String? get connectedDeviceName =>
      (_connectedDevice ?? (isCasting ? _lastDevice : null))?.friendlyName;
  CastRemoteState get remoteState => _remote;

  Track? get remoteTrack => _castSnapshot?.queue.currentEntry?.track;
  int get remoteIndex => _castSnapshot?.queue.currentIndex ?? 0;
  String? get remoteEntryId => _castSnapshot?.queue.currentEntry?.id;
  bool get castShuffle => _castSnapshot?.queue.shuffle ?? false;
  LoopMode get castRepeatMode => _castSnapshot?.repeatMode ?? LoopMode.off;

  List<Track> get castHistory =>
      List.unmodifiable(_castSnapshot?.history ?? const []);

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
  Stream<Duration> get positionStream => _sender.remoteStateStream
      .where((state) => !_isStale(state))
      .map((state) => state.position);
  String? get error => _error;
  JellyfinSession? get session => _session;

  bool get canCast {
    if (!_isSupported() || _session == null) return false;
    if (_playback.currentTrack == null) return false;
    return _serverBlocker() == null;
  }

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
        _safeNotify();
      });
      _connectionSub ??= _sender.connectionStateStream.listen(_onConnection);
      _remoteSub ??= _sender.remoteStateStream.listen(_onRemote);
      _receiverMessagesSub ??= _sender.receiverMessages.listen(
        _onReceiverMessage,
      );
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
  /// An account change (including sign-out) immediately invalidates
  /// in-flight work. Unchanged-account configuration never ends Cast.
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
    _cancelTimers();
    if (_ownership == CastOwnership.local &&
        _castSnapshot == null &&
        _sender.connectionState == CastConnectionState.disconnected) {
      _safeNotify();
      return;
    }
    _leavingRemote = true;
    try {
      await _sender.disconnect(stopReceiver: true);
    } catch (_) {
      // Best-effort on the receiver; the local transition below still runs
      // so no stale snapshot can revive.
    } finally {
      _leavingRemote = false;
    }
    if (generation != _generation) return;
    _connection = CastConnectionState.disconnected;
    _connectedDevice = null;
    _forgetReceiver();
    _castSnapshot = null;
    _lastDevice = null;
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

  // ---------------------------------------------------------------------------
  // Transport events

  void _onConnection(CastConnectionState state) {
    _connection = state;
    _connectedDevice = _sender.connectedDevice;
    switch (state) {
      case CastConnectionState.disconnected:
        _connectedDevice = null;
        if (_ownership == CastOwnership.remote && !_leavingRemote) {
          _setOwnership(CastOwnership.recovering);
          _startSessionLossTimer();
        }
      case CastConnectionState.connected:
        if (_ownership == CastOwnership.recovering) {
          _cancelSessionLossTimer();
          _runInBackground(_adoptReceiverNow);
        }
      case CastConnectionState.connecting:
        break;
    }
    _safeNotify();
  }

  void _onRemote(CastRemoteState state) {
    if (_isStale(state) || _isTransportReset(state)) {
      // Volume belongs to the device, not the media item.
      if (state.volume != _remote.volume) {
        _remote = _remote.copyWith(volume: state.volume);
        _safeNotify();
      }
      return;
    }
    final arrived = _awaiting;
    if (arrived != null && state.itemId == arrived.track.id) {
      _awaiting = null;
      _awaitingSince = null;
    }
    _remote = state;
    _adoptRecovery(state);
    _pauseIfRequested(state);
    if (_ownership == CastOwnership.remote) _followReceiver(state);
    _safeNotify();
  }

  /// A dropped session resets the sender's transport state; keep showing the
  /// last known track and position while rejoining.
  bool _isTransportReset(CastRemoteState state) =>
      isCasting &&
      state.playerState == CastPlayerState.unknown &&
      state.itemId == null;

  /// Status for an item other than the one just requested belongs to the
  /// previous load. A receiver that never reports the request is followed
  /// again after [_awaitTimeout].
  bool _isStale(CastRemoteState state) {
    final awaiting = _awaiting;
    if (awaiting == null) return false;
    if (state.itemId == awaiting.track.id) return false;
    final since = _awaitingSince;
    if (since != null && DateTime.now().difference(since) > _awaitTimeout) {
      _awaiting = null;
      _awaitingSince = null;
      return false;
    }
    return true;
  }

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

  void _pauseIfRequested(CastRemoteState state) {
    final entryId = _pauseOnArrival;
    if (entryId == null || state.itemId == null) return;
    if (state.playerState != CastPlayerState.playing) return;
    _pauseOnArrival = null;
    unawaited(_sender.pause().catchError((Object _) {}));
  }

  /// Moves the desired queue to the occurrence the receiver advanced to.
  void _followReceiver(CastRemoteState state) {
    final itemId = state.itemId;
    final receiver = _receiver;
    final snapshot = _castSnapshot;
    if (itemId == null || receiver == null || snapshot == null) return;
    if (receiver.current?.track.id == itemId) return;
    final at = receiver.locate(itemId);
    if (at == null) return;
    final reached = receiver.entries[at];
    final queue = snapshot.queue.selectEntry(reached.id);
    final stillQueued = queue.currentEntry?.id == reached.id;
    if (!stillQueued || _resyncPending) {
      if (_correcting) return;
      _correcting = true;
      _runInBackground(_playDesiredNextNow);
      return;
    }
    _receiver = receiver.at(at);
    _castSnapshot = snapshot.copyWith(queue: queue);
    if (_needsMoreQueue()) _runInBackground(_extendReceiverNow);
  }

  bool get _resyncPending => _resyncTimer != null || _resyncOnPlay;

  bool _needsMoreQueue() {
    final queue = _castSnapshot?.queue;
    final receiver = _receiver;
    if (queue == null || receiver == null) return false;
    final current = queue.currentIndex;
    return queue.hasUnloadedTail &&
        current != null &&
        queue.loadedEntries.length - current <= _queueExtensionThreshold;
  }

  void _onReceiverMessage(String raw) {
    if (!isCasting) return;
    final message = JellyfinReceiverProtocol.errorFromReceiverMessage(raw);
    if (message != null) _fail(message);
  }

  // ---------------------------------------------------------------------------
  // Connect and handoff

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

  /// Hands the local queue to the receiver at the current position.
  ///
  /// The local queue is snapshotted (not mutated) and local audio is stopped
  /// with local reports suppressed: the receiver reports to the server.
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
    if (_playback.currentTrack == null) {
      throw const CastException('Nothing playing to cast.');
    }
    if (_connection != CastConnectionState.connected &&
        _connectedDevice == null) {
      throw const CastException('Connect to a Chromecast first.');
    }
    final localSnapshot = _playback.captureSnapshot();
    final position = _playback.position;
    final current = localSnapshot.queue.currentEntry;
    if (current == null) throw const CastException('Nothing playing to cast.');

    _setOwnership(CastOwnership.transferring);
    await _playback.stopForCast();
    _playback.setCastingActive(true);
    try {
      await _sender.sendReceiverCommand(
        JellyfinReceiverProtocol.setRepeatMode(
          session,
          localSnapshot.repeatMode,
        ),
      );
      if (generation != _generation) return;
      _castSnapshot = localSnapshot;
      await _playOnReceiver(
        localSnapshot.queue,
        current,
        position: position,
        autoplay: true,
      );
    } catch (_) {
      _castSnapshot = null;
      _forgetReceiver();
      await _abortHandoff(localSnapshot, generation);
      rethrow;
    }
    if (generation != _generation) return;
    _setOwnership(CastOwnership.remote);
    _error = null;
    _safeNotify();
  }

  /// Restores local playback after a failed handoff. When the receiver can
  /// not be stopped, Cast ownership is kept for the user to decide.
  Future<void> _abortHandoff(
    PlaybackSnapshot localSnapshot,
    int generation,
  ) async {
    try {
      await _sender.stop();
    } catch (_) {
      // Nothing may have loaded on the receiver yet; stopping is best-effort.
    }
    if (generation != _generation) return;
    try {
      await _playback.restoreSnapshot(localSnapshot);
    } catch (_) {
      _castSnapshot = localSnapshot;
      _setOwnership(CastOwnership.recovering);
      rethrow;
    }
    _playback.setCastingActive(false);
    _setOwnership(CastOwnership.local);
    await _playback.reportCurrentState();
  }

  // ---------------------------------------------------------------------------
  // Receiver queue primitives

  /// Sends [queue] to the receiver starting at [target], then commits it as
  /// the desired queue. A failed send keeps the prior state.
  Future<void> _playOnReceiver(
    QueueState queue,
    QueueEntry target, {
    required Duration position,
    required bool autoplay,
    List<Track>? history,
  }) async {
    final session = _session;
    final snapshot = _castSnapshot;
    if (session == null || snapshot == null) {
      throw const CastException('Nothing is casting right now.');
    }
    final selected = queue.selectEntry(target.id);
    final receiver = ReceiverQueue.around(
      selected,
      fromStart: castRepeatMode == LoopMode.all,
    );
    await _sendExpecting(
      JellyfinReceiverProtocol.playNow(
        session,
        itemIds: receiver.itemIds,
        startIndex: receiver.index,
        startPosition: position,
      ),
      receiver: receiver,
      target: target,
      position: position,
      autoplay: autoplay,
    );
    _resyncTimer?.cancel();
    _resyncTimer = null;
    _resyncOnPlay = false;
    _castSnapshot = snapshot.copyWith(
      queue: selected,
      position: position,
      playing: autoplay,
      history: history,
    );
    _recoveryPosition = position;
    _recoveryPlaying = autoplay;
    _safeNotify();
  }

  /// Sends a command that makes the receiver play [target]. The mirror and
  /// expectation are in place before sending, because the receiver can
  /// report the new item before the send completes; a failed send restores
  /// them.
  Future<void> _sendExpecting(
    Map<String, Object?> command, {
    required ReceiverQueue receiver,
    required QueueEntry target,
    required Duration position,
    required bool autoplay,
  }) async {
    final priorReceiver = _receiver;
    final priorRemote = _remote;
    _receiver = receiver;
    _expect(target, autoplay: autoplay);
    _remote = CastRemoteState(
      playerState: CastPlayerState.buffering,
      position: position,
      duration: Duration(microseconds: target.track.durationTicks ~/ 10),
      volume: _remote.volume,
      itemId: target.track.id,
    );
    try {
      await _sender.sendReceiverCommand(command);
    } catch (_) {
      _receiver = priorReceiver;
      _awaiting = null;
      _awaitingSince = null;
      _pauseOnArrival = null;
      _remote = priorRemote;
      rethrow;
    }
  }

  void _expect(QueueEntry target, {required bool autoplay}) {
    _awaiting = target;
    _awaitingSince = DateTime.now();
    _pauseOnArrival = autoplay ? null : target.id;
  }

  /// Brings the receiver in line with the desired queue after an edit:
  /// appends what it lacks, or reloads it when its upcoming order differs.
  void _reconcileReceiver() {
    final queue = _castSnapshot?.queue;
    final receiver = _receiver;
    if (queue == null || receiver == null) return;
    final missing = receiver.missingTail(queue);
    if (missing == null) {
      _scheduleResync();
    } else if (missing.isNotEmpty) {
      _runInBackground(_extendReceiverNow);
    }
  }

  Future<void> _extendReceiverNow(int generation) async {
    final session = _session;
    var snapshot = _castSnapshot;
    if (session == null || snapshot == null || _receiver == null) return;
    if (_ownership != CastOwnership.remote) return;
    if (_needsMoreQueue()) {
      snapshot = snapshot.copyWith(queue: snapshot.queue.extend());
      _castSnapshot = snapshot;
    }
    final missing = _receiver!.missingTail(snapshot.queue);
    if (missing == null) {
      _scheduleResync();
      return;
    }
    if (missing.isEmpty) return;
    final batch = missing
        .take(JellyfinReceiverProtocol.maxItemsPerMessage)
        .toList();
    await _sender.sendReceiverCommand(
      JellyfinReceiverProtocol.playLast(
        session,
        itemIds: [for (final entry in batch) entry.track.id],
      ),
    );
    if (generation != _generation) return;
    _receiver = _receiver?.appended(batch);
    _safeNotify();
  }

  void _scheduleResync() {
    _resyncTimer?.cancel();
    _resyncTimer = null;
    if (_disposed) return;
    if (!_recoveryPlaying) {
      _resyncOnPlay = true;
      return;
    }
    _resyncTimer = Timer(resyncDelay, () {
      _resyncTimer = null;
      _runInBackground(_resyncNow);
    });
  }

  /// Reloads the receiver with the desired queue at the current entry and
  /// position, so a reorder or removal reaches it.
  Future<void> _resyncNow(int generation) async {
    _resyncTimer?.cancel();
    _resyncTimer = null;
    final snapshot = _castSnapshot;
    final receiver = _receiver;
    if (snapshot == null || receiver == null) return;
    if (_ownership != CastOwnership.remote) return;
    final current = snapshot.queue.currentEntry;
    if (current == null) return;
    if (receiver.current?.id == current.id) {
      final missing = receiver.missingTail(snapshot.queue);
      if (missing != null) {
        if (missing.isNotEmpty) await _extendReceiverNow(generation);
        return;
      }
    }
    await _playOnReceiver(
      snapshot.queue,
      current,
      position: _recoveryPosition,
      autoplay: _recoveryPlaying,
    );
  }

  /// The receiver finished the current entry before a pending edit reached
  /// it, so it advanced in its stale order. Plays the phone's next entry.
  Future<void> _playDesiredNextNow(int generation) async {
    _correcting = false;
    final queue = _castSnapshot?.queue;
    if (queue == null || _ownership != CastOwnership.remote) return;
    final at = (queue.currentIndex ?? -1) + 1;
    if (at >= queue.loadedEntries.length) {
      await _sender.stop();
      return;
    }
    await _playOnReceiver(
      queue,
      queue.loadedEntries[at],
      position: Duration.zero,
      autoplay: true,
    );
  }

  // ---------------------------------------------------------------------------
  // Transport commands

  Future<void> play() => _castGuarded(_resumeNow);
  Future<void> pause() => _castGuarded(() => _sender.pause());

  Future<void> toggle() => _castGuarded(() async {
    if (_remote.isPlaying) {
      await _sender.pause();
    } else {
      await _resumeNow();
    }
  });

  /// Resumes the receiver, reloading the current entry when the receiver has
  /// gone idle (queue ended, or the receiver app was restarted).
  Future<void> _resumeNow() async {
    final snapshot = _castSnapshot;
    final current = snapshot?.queue.currentEntry;
    final idle =
        _remote.playerState == CastPlayerState.idle || _remote.itemId == null;
    if ((idle || _resyncOnPlay) && snapshot != null && current != null) {
      final ended = _remote.finishReason == CastFinishReason.finished;
      await _playOnReceiver(
        snapshot.queue,
        current,
        position: ended ? Duration.zero : _recoveryPosition,
        autoplay: true,
      );
      return;
    }
    await _sender.play();
  }

  Future<void> seek(Duration position) => _castGuarded(() async {
    final session = _session;
    if (session == null) {
      throw const CastException('Nothing is casting right now.');
    }
    final duration = remoteDuration;
    final safe = position.isNegative
        ? Duration.zero
        : (duration != null && position > duration ? duration : position);
    await _sender.sendReceiverCommand(
      JellyfinReceiverProtocol.seek(session, safe),
    );
    _recoveryPosition = safe;
    _remote = _remote.copyWith(position: safe);
    _safeNotify();
  });

  Future<void> setVolume(double volume) =>
      _castGuarded(() => _sender.setVolume(volume.clamp(0.0, 1.0)));

  Future<void> next() => _remoteGuarded(_nextNow);

  Future<void> _nextNow(int generation) async {
    final session = _session;
    var snapshot = _castSnapshot;
    if (session == null || snapshot == null) {
      throw const CastException('Nothing is casting right now.');
    }
    var queue = snapshot.queue;
    final at = (queue.currentIndex ?? -1) + 1;
    if (at >= queue.loadedEntries.length && queue.hasUnloadedTail) {
      queue = queue.extend();
      snapshot = snapshot.copyWith(queue: queue);
      _castSnapshot = snapshot;
    }
    if (at >= queue.loadedEntries.length && castRepeatMode == LoopMode.all) {
      queue = QueueState.restore(
        queue.collectionTracks,
        index: 0,
        shuffle: queue.shuffle,
        newId: _newCastId,
      );
      final first = queue.currentEntry;
      if (first == null) return;
      await _playOnReceiver(
        queue,
        first,
        position: Duration.zero,
        autoplay: true,
      );
      return;
    }
    if (at >= queue.loadedEntries.length) {
      throw const CastException('You’re at the end of the queue.');
    }
    final target = queue.loadedEntries[at];
    final receiver = _receiver;
    // The receiver's NextTrack replays the current item under repeat one.
    final inSync =
        castRepeatMode != LoopMode.one &&
        !_resyncPending &&
        receiver != null &&
        receiver.current?.id == queue.currentEntry?.id &&
        receiver.next?.id == target.id;
    if (!inSync) {
      await _playOnReceiver(
        queue,
        target,
        position: Duration.zero,
        autoplay: true,
      );
      return;
    }
    await _sendExpecting(
      JellyfinReceiverProtocol.nextTrack(session),
      receiver: receiver.at(receiver.index + 1),
      target: target,
      position: Duration.zero,
      autoplay: true,
    );
    if (generation != _generation) return;
    _castSnapshot = snapshot.copyWith(
      queue: queue.selectEntry(target.id),
      position: Duration.zero,
      playing: true,
    );
    _recoveryPosition = Duration.zero;
    _recoveryPlaying = true;
    if (_needsMoreQueue()) _runInBackground(_extendReceiverNow);
    _safeNotify();
  }

  Future<void> previous() => _remoteGuarded((generation) async {
    final session = _session;
    final snapshot = _castSnapshot;
    if (session == null || snapshot == null) {
      throw const CastException('Nothing is casting right now.');
    }
    final queue = snapshot.queue;
    final at = (queue.currentIndex ?? 0) - 1;
    // Mirror local behavior: restart the track when well into it.
    if (_remote.position > const Duration(seconds: 4) || at < 0) {
      await _sender.sendReceiverCommand(
        JellyfinReceiverProtocol.seek(session, Duration.zero),
      );
      _recoveryPosition = Duration.zero;
      return;
    }
    await _playOnReceiver(
      queue,
      queue.loadedEntries[at],
      position: Duration.zero,
      autoplay: true,
    );
  });

  /// Jumps the receiver to a queue index (queue taps while casting).
  Future<void> playIndex(int index) => _remoteGuarded((generation) async {
    final snapshot = _castSnapshot;
    if (snapshot == null || snapshot.queue.loadedEntries.isEmpty) {
      throw const CastException('Nothing is casting right now.');
    }
    final queue = snapshot.queue;
    final at = index.clamp(0, queue.loadedEntries.length - 1);
    await _playOnReceiver(
      queue,
      queue.loadedEntries[at],
      position: Duration.zero,
      autoplay: true,
    );
  });

  // ---------------------------------------------------------------------------
  // Queue edits (same names and meanings as local playback)

  Future<void> replaceQueue(
    List<Track> tracks, {
    int? startIndex,
    bool? shuffle,
  }) => _remoteGuarded(
    (generation) =>
        _replaceQueueNow(tracks, startIndex: startIndex, shuffle: shuffle),
  );

  Future<void> _replaceQueueNow(
    List<Track> tracks, {
    int? startIndex,
    bool? shuffle,
  }) async {
    final snapshot = _castSnapshot;
    if (snapshot == null) {
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
    final target = candidate.currentEntry;
    if (target == null) return;
    await _playOnReceiver(
      candidate,
      target,
      position: Duration.zero,
      autoplay: true,
    );
  }

  Future<void> playTrack(Track track, List<Track> context) =>
      _remoteGuarded((generation) async {
        final index = context.indexWhere((item) => item.id == track.id);
        await _replaceQueueNow(context, startIndex: index < 0 ? 0 : index);
      });

  Future<void> addToQueue(Track track) =>
      _editQueue((queue) => queue.append(track, newId: _newCastId));

  Future<void> addNextToQueue(List<Track> tracks) => _editQueue(
    (queue) =>
        tracks.isEmpty ? queue : queue.insertNext(tracks, newId: _newCastId),
  );

  Future<void> replaceUpcoming(List<Track> tracks) =>
      _editQueue((queue) => queue.replaceUpcoming(tracks, newId: _newCastId));

  Future<void> reorder(int oldIndex, int newIndex) =>
      _editQueue((queue) => queue.reorder(oldIndex, newIndex));

  Future<void> toggleShuffle() => _editQueue(
    (queue) => queue.shuffle
        ? queue.withShuffle(false)
        : queue.withShuffle(true).shuffleRemaining(random: _random),
  );

  /// Applies an edit that keeps the current entry playing, then brings the
  /// receiver in line without interrupting audio when possible.
  Future<void> _editQueue(QueueState Function(QueueState queue) edit) =>
      _remoteGuarded((_) async {
        final snapshot = _castSnapshot;
        if (snapshot == null) {
          throw const CastException('Nothing is casting right now.');
        }
        final candidate = edit(snapshot.queue);
        if (identical(candidate, snapshot.queue)) return;
        _castSnapshot = snapshot.copyWith(queue: candidate);
        _reconcileReceiver();
        _safeNotify();
      });

  Future<void> removeAt(int index) => _remoteGuarded((_) async {
    final queue = _castSnapshot?.queue;
    if (queue == null) {
      throw const CastException('Nothing is casting right now.');
    }
    if (index < 0 || index >= queue.loadedEntries.length) return;
    final removed = queue.loadedEntries[index];
    await _commitRemoval(
      candidate: queue.removeAt(index),
      removedCurrent: removed.id == queue.currentEntry?.id,
    );
  });

  Future<void> removeTrack(String trackId) => _remoteGuarded((_) async {
    final queue = _castSnapshot?.queue;
    if (queue == null) {
      throw const CastException('Nothing is casting right now.');
    }
    final candidate = queue.removeTrack(trackId);
    if (identical(candidate, queue)) return;
    final before = queue.currentEntry?.id;
    final kept =
        before != null &&
        candidate.loadedEntries.any((entry) => entry.id == before);
    await _commitRemoval(candidate: candidate, removedCurrent: !kept);
  });

  /// Removing the current entry plays its successor (keeping play/pause);
  /// removing the final entry stops the receiver and keeps the connection.
  Future<void> _commitRemoval({
    required QueueState candidate,
    required bool removedCurrent,
  }) async {
    final snapshot = _castSnapshot;
    if (snapshot == null) return;
    if (!removedCurrent) {
      _castSnapshot = snapshot.copyWith(queue: candidate);
      _reconcileReceiver();
      _safeNotify();
      return;
    }
    final successor = candidate.currentEntry;
    if (successor == null) {
      await _sender.stop();
      _castSnapshot = snapshot.copyWith(
        queue: candidate,
        position: Duration.zero,
        playing: false,
      );
      _forgetReceiver();
      _recoveryPosition = Duration.zero;
      _recoveryPlaying = false;
      _safeNotify();
      return;
    }
    await _playOnReceiver(
      candidate,
      successor,
      position: Duration.zero,
      autoplay: _recoveryPlaying,
    );
  }

  Future<void> playHistoryTrack(Track track) => _remoteGuarded((_) async {
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
    final target = inserted.loadedEntries[(inserted.currentIndex ?? -1) + 1];
    await _playOnReceiver(
      inserted,
      target,
      position: Duration.zero,
      autoplay: true,
      history: history,
    );
  });

  String _newCastId() => 'cast-${_castIds++}';

  // ---------------------------------------------------------------------------
  // Reconnect

  /// Reconnects to the last device and continues where Cast left off.
  Future<void> retry() => _enqueue((generation) async {
    _cancelSessionLossTimer();
    await _rejoinNow(generation);
  });

  void _startSessionLossTimer() {
    _cancelSessionLossTimer();
    if (_disposed || !_foreground) return;
    if (_ownership != CastOwnership.recovering) return;
    _sessionLossTimer = Timer(sessionLossGrace, () {
      _sessionLossTimer = null;
      _runInBackground(_returnToPhoneAfterLossNow);
    });
  }

  void _cancelSessionLossTimer() {
    _sessionLossTimer?.cancel();
    _sessionLossTimer = null;
  }

  /// The session ended elsewhere (TV, Google Home, another app) or never
  /// came back: the queue returns to the phone, paused where Cast was.
  Future<void> _returnToPhoneAfterLossNow(int generation) async {
    if (_ownership != CastOwnership.recovering) return;
    if (_sender.connectionState != CastConnectionState.disconnected) return;
    final name = _lastDevice?.friendlyName ?? 'Chromecast';
    await _disconnectNow(false, generation);
    if (generation != _generation) return;
    _fail('Casting to $name ended. Playback is back on this phone.');
  }

  Future<void> _rejoinNow(int generation) async {
    final device = _lastDevice;
    if (device == null || _castSnapshot == null || _session == null) {
      throw const CastException(
        'Nothing to reconnect. Pick a Chromecast and try again.',
      );
    }
    if (_ownership == CastOwnership.remote &&
        _sender.connectionState == CastConnectionState.connected) {
      return;
    }
    await _initializeNow();
    if (generation != _generation) return;
    if (_sender.connectionState == CastConnectionState.disconnected) {
      await _sender.connect(device);
    }
    await _waitForConnection();
    if (generation != _generation) return;
    _connection = _sender.connectionState;
    _connectedDevice = _sender.connectedDevice ?? device;
    await _adoptReceiverNow(generation);
  }

  /// After a rejoin, follows what the receiver is playing; when it lost our
  /// queue (receiver app restarted), reloads it where Cast left off.
  Future<void> _adoptReceiverNow(int generation) async {
    final snapshot = _castSnapshot;
    if (snapshot == null || _ownership == CastOwnership.local) return;
    if (_ownership == CastOwnership.remote) return;
    final itemId = await _receiverItemAfterJoin();
    if (generation != _generation || _castSnapshot == null) return;
    _awaiting = null;
    _awaitingSince = null;
    final receiver = _receiver;
    final at = itemId == null ? null : receiver?.locate(itemId);
    await _registerAsReceiverSender();
    if (generation != _generation || _castSnapshot == null) return;
    if (receiver != null && at != null) {
      _setOwnership(CastOwnership.remote);
      _error = null;
      _followReceiver(_remote);
      _safeNotify();
      return;
    }
    _showLostReceiverQueuePaused();
    _setOwnership(CastOwnership.remote);
    _error = null;
    _safeNotify();
  }

  /// The receiver sends its errors to the sender of its last command, so a
  /// rejoined phone announces itself with a harmless command.
  Future<void> _registerAsReceiverSender() async {
    final session = _session;
    if (session == null) return;
    try {
      await _sender.sendReceiverCommand(
        JellyfinReceiverProtocol.setRepeatMode(session, castRepeatMode),
      );
    } on CastException {
      // Only error routing depends on it; playback control still works.
    }
  }

  /// The receiver finished the queue or was restarted while the phone was
  /// away. Never restart audio by surprise: show where Cast stopped, paused;
  /// play reloads it.
  void _showLostReceiverQueuePaused() {
    final current = _castSnapshot?.queue.currentEntry;
    _receiver = null;
    _recoveryPlaying = false;
    _remote = CastRemoteState(
      playerState: CastPlayerState.idle,
      position: _recoveryPosition,
      duration: current == null
          ? null
          : Duration(microseconds: current.track.durationTicks ~/ 10),
      volume: _remote.volume,
    );
  }

  Future<String?> _receiverItemAfterJoin() async {
    final known = _sender.remoteState.itemId;
    if (known != null) return known;
    try {
      final state = await _sender.remoteStateStream
          .firstWhere((state) => state.itemId != null)
          .timeout(adoptTimeout);
      return state.itemId;
    } on TimeoutException {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Disconnect

  /// Ends the Cast session and resumes local playback where Cast left off.
  ///
  /// `resumeLocal:false` restores the queue paused; account invalidation
  /// discards it. Receiver shutdown or restore failure keeps recovery data
  /// and reports the error without starting local audio.
  Future<void> disconnect({bool resumeLocal = true}) =>
      _enqueue((generation) => _disconnectNow(resumeLocal, generation));

  Future<void> _disconnectNow(bool resumeLocal, int generation) async {
    final position = _recoveryPosition;
    final resumePlaying = resumeLocal && _recoveryPlaying;
    final snapshot = _castSnapshot;
    if (snapshot == null &&
        _ownership == CastOwnership.local &&
        _sender.connectionState == CastConnectionState.disconnected) {
      return;
    }
    _cancelTimers();
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
    _forgetReceiver();
    if (_session == null || snapshot == null) {
      _castSnapshot = null;
      _playback.setCastingActive(false);
      _setOwnership(CastOwnership.local);
      _safeNotify();
      return;
    }
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
    _error = null;
    _safeNotify();
  }

  // ---------------------------------------------------------------------------
  // App lifecycle

  /// Resumes discovery and rejoins a dropped session when the app returns.
  ///
  /// iOS suspends Cast sessions in the background and resumes them on
  /// return; the rejoin only runs when that automatic resume does not.
  Future<void> handleAppForeground() async {
    _foreground = true;
    if (!_initialized) return;
    try {
      await _sender.startDiscovery();
    } catch (_) {}
    _connection = _sender.connectionState;
    if (_ownership == CastOwnership.recovering) _startSessionLossTimer();
    _safeNotify();
  }

  /// Pauses discovery and rejoin attempts in the background. The receiver
  /// keeps playing its queue (`stopCastingOnAppTerminated=false`).
  Future<void> handleAppBackground() async {
    _foreground = false;
    _cancelSessionLossTimer();
    try {
      await _sender.stopDiscovery();
    } catch (_) {}
  }

  void clearError() {
    _error = null;
    _safeNotify();
  }

  // ---------------------------------------------------------------------------
  // Lane and helpers

  Future<void> _castGuarded(Future<void> Function() action) =>
      _enqueue((_) async {
        if (_ownership != CastOwnership.remote) {
          throw CastException(
            _ownership == CastOwnership.recovering
                ? 'Reconnecting to Chromecast. Try again in a moment.'
                : 'Nothing is casting right now.',
          );
        }
        await action();
      });

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

  /// Runs follow-up work on the lane without a caller to report to; errors
  /// still surface through [error].
  void _runInBackground(Future<void> Function(int generation) task) {
    unawaited(_enqueue(task).catchError((Object _) {}));
  }

  /// Orders commands instead of dropping busy calls. Errors surface through
  /// [error] and the caller; stale generations return silently.
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
          (_) {},
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

  void _forgetReceiver() {
    _receiver = null;
    _awaiting = null;
    _awaitingSince = null;
    _pauseOnArrival = null;
    _resyncTimer?.cancel();
    _resyncTimer = null;
  }

  void _cancelTimers() {
    _resyncTimer?.cancel();
    _resyncTimer = null;
    _resyncOnPlay = false;
    _correcting = false;
    _cancelSessionLossTimer();
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
    _generation++;
    _disposed = true;
    _cancelTimers();
    _devicesSub?.cancel();
    _connectionSub?.cancel();
    _remoteSub?.cancel();
    _receiverMessagesSub?.cancel();
    super.dispose();
  }
}
