import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../storage/database.dart';
import '../jellyfin/session.dart';
import '../playback/playback_snapshot.dart';
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
    // ignore: prefer_initializing_formals
  }) : _playback = playback,
       // ignore: prefer_initializing_formals
       _adapter = adapter,
       // ignore: prefer_initializing_formals
       _sender = sender,
       // ignore: prefer_initializing_formals
       _isSupported = isSupported ?? (() => isCastPlatformSupported);

  final CastPlaybackSource _playback;
  final JellyfinCastAdapter _adapter;
  final CastSender _sender;
  final bool Function() _isSupported;

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

  List<Track> _snapshot = const [];
  int _remoteIndex = 0;
  Track? _remoteTrack;

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
  Track? get remoteTrack => _remoteTrack;
  int get remoteIndex => _remoteIndex;

  /// Queue snapshot taken at handoff. Remote next/previous/playIndex resolve
  /// against this list; the local queue is never mutated while casting.
  List<Track> get castQueue => List.unmodifiable(_snapshot);
  Duration get remotePosition => _remote.position;
  Duration? get remoteDuration {
    if (_remote.duration != null) return _remote.duration;
    final track = _remoteTrack;
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

  Future<void> setReceiverChannel(bool unstable) =>
      _enqueue((_) async {
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
    if (_playback.currentTrack != null &&
        _ownership == CastOwnership.local) {
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
    final queue = List<Track>.of(_playback.queue);
    final index =
        _playback.currentIndex ??
        queue.indexWhere((item) => item.id == track.id);
    final safeIndex = index < 0 ? 0 : index;
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
        playlistItemId: null,
        autoplay: true,
      );
    } catch (error) {
      await _abortHandoff(localSnapshot, generation);
      rethrow;
    }
    if (generation != _generation) return;
    _snapshot = queue.isEmpty ? [track] : queue;
    _remoteIndex = safeIndex.clamp(0, _snapshot.length - 1);
    _remoteTrack = track;
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

  Future<void> next() => _castGuarded(() async {
    if (_snapshot.isEmpty) {
      await _sender.next();
      return;
    }
    final at = _remoteIndex + 1;
    if (at >= _snapshot.length) {
      throw const CastException('You\u2019re at the end of the queue.');
    }
    await _loadSnapshotIndex(at, autoplay: true);
  });

  Future<void> previous() => _castGuarded(() async {
    // Mirror local behavior: restart the track when well into it.
    if (_remote.position > const Duration(seconds: 4)) {
      await _sender.seek(Duration.zero);
      _recoveryPosition = Duration.zero;
      return;
    }
    if (_snapshot.isEmpty) {
      await _sender.previous();
      return;
    }
    final at = _remoteIndex - 1;
    if (at < 0) {
      await _sender.seek(Duration.zero);
      _recoveryPosition = Duration.zero;
      return;
    }
    await _loadSnapshotIndex(at, autoplay: true);
  });

  /// Jumps the receiver to a snapshot index (queue taps while casting).
  Future<void> playIndex(int index) => _castGuarded(() async {
    if (_snapshot.isEmpty) throw const CastException('Nothing is casting.');
    final at = index.clamp(0, _snapshot.length - 1);
    if (at == _remoteIndex) {
      await _sender.seek(Duration.zero);
      _recoveryPosition = Duration.zero;
      return;
    }
    await _loadSnapshotIndex(at, autoplay: true);
  });

  Future<void> _loadSnapshotIndex(int at, {required bool autoplay}) async {
    final session = _session;
    if (session == null) throw const CastException('Sign in to cast.');
    final track = _snapshot[at];
    await _loadWithFallback(
      session,
      track,
      Duration.zero,
      playlistItemId: null,
      autoplay: autoplay,
    );
    _remoteIndex = at;
    _remoteTrack = track;
    _recoveryPosition = Duration.zero;
    _recoveryPlaying = autoplay;
    // Track receiver selection in the retained snapshot so resume restores
    // the current Cast state. The loaded order matches the handoff queue
    // (edits arrive with the Cast queue work); duplicates resolve by
    // position until occurrence-based edits land.
    final retained = _castSnapshot;
    if (retained != null) {
      final loaded = retained.queue.loadedEntries;
      if (at >= 0 && at < loaded.length) {
        _castSnapshot = retained.copyWith(
          queue: retained.queue.selectEntry(loaded[at].id),
          position: Duration.zero,
          playing: autoplay,
        );
      }
    }
    _safeNotify();
  }

  /// Reconnects to the last target and reloads at the last usable position.
  ///
  /// The recovery decision is captured before the first await and passed as
  /// `autoplay` through both normal and AAC-fallback loads; load events
  /// never re-read a flag the load itself may change.
  Future<void> retry() =>
      _enqueue((generation) => _retryNow(generation));

  Future<void> _retryNow(int generation) async {
    final device = _lastDevice;
    final track = _remoteTrack;
    final session = _session;
    if (device == null || track == null || session == null) {
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
      track,
      position,
      playlistItemId: null,
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
      _snapshot = const [];
      _remoteTrack = null;
      _remoteIndex = 0;
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
    _snapshot = const [];
    _remoteTrack = null;
    _remoteIndex = 0;
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

  Future<void> _castGuarded(Future<void> Function() action) => _enqueue(
    (_) async {
      if (!isCasting) {
        throw const CastException('Nothing is casting right now.');
      }
      await action();
    },
  );

  /// Orders commands instead of silently dropping busy calls. Errors surface
  /// through [error] and the caller; stale generations return silently; the
  /// lane itself never breaks.
  Future<void> _enqueue(Future<void> Function(int generation) task) {
    if (_disposed) return Future.value();
    final generation = _generation;
    _inflight++;
    _safeNotify();
    final result = _commands.then((_) {
      if (generation != _generation || _disposed) {
        return Future<void>.value();
      }
      return task(generation);
    }).then((_) {
      // Preserve the error value for the caller without breaking the lane.
    }, onError: (Object error) {
      if (error is CastException) {
        _fail(error.message);
      } else {
        final message = redactSecrets(error);
        _fail(message);
        throw CastException(message);
      }
      throw error;
    });
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
