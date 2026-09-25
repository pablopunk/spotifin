import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../storage/database.dart';
import '../jellyfin/session.dart';
import '../redaction.dart';
import 'cast_device.dart';
import 'cast_playback_source.dart';
import 'cast_sender.dart';
import 'jellyfin_cast_adapter.dart';

/// Orchestrates the iPhone Chromecast MVP.
///
/// Flow: discover → connect → hand off the current track (title/artist/
/// album/artwork/duration/position) to the Jellyfin Web Receiver → drive
/// play/pause/seek/volume/next/previous remotely → disconnect resumes local
/// playback at the remote position. The local queue/history is never mutated
/// while casting: a snapshot is taken at handoff and only used to resolve
/// next/previous and to resume afterwards.
///
/// Failure handling is explicit and user-visible via [error]: sign-in
/// required, server unreachable by Cast (plain HTTP/localhost), nothing to
/// cast, unsupported platform, target disappearance, failed handoff (with a
/// one-time AAC fallback retry), connection loss (retry or resume locally),
/// and background/foreground transitions (discovery paused/resumed).
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
  bool _busy = false;
  bool _casting = false;

  List<CastDevice> _devices = const [];
  CastConnectionState _connection = CastConnectionState.disconnected;
  CastDevice? _connectedDevice;
  CastRemoteState _remote = const CastRemoteState();

  List<Track> _snapshot = const [];
  int _remoteIndex = 0;
  Track? _remoteTrack;
  Duration _lastKnownPosition = Duration.zero;
  bool _lastKnownPlaying = false;
  CastDevice? _lastDevice;

  String? _error;

  StreamSubscription<List<CastDevice>>? _devicesSub;
  StreamSubscription<CastConnectionState>? _connectionSub;
  StreamSubscription<CastRemoteState>? _remoteSub;

  bool get initialized => _initialized;
  bool get initializing => _initializing;
  bool get busy => _busy;
  bool get isCasting => _casting;
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

  Future<void> initialize() async {
    if (_initialized || _initializing) return;
    _initializing = true;
    notifyListeners();
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
        notifyListeners();
      });
      _connectionSub ??= _sender.connectionStateStream.listen(_onConnection);
      _remoteSub ??= _sender.remoteStateStream.listen((state) {
        _remote = state;
        _lastKnownPosition = state.position;
        _lastKnownPlaying = state.isPlaying;
        notifyListeners();
      });
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
      notifyListeners();
    }
  }

  void configure(JellyfinSession? session) {
    _session = session;
    if (session == null && _casting) {
      // Signed out mid-cast: stop remote, keep local halted; the UI offers
      // resume once the user signs back in.
      unawaited(disconnect(resumeLocal: false));
    }
    notifyListeners();
  }

  Future<void> setReceiverChannel(bool unstable) async {
    if (_unstableReceiver == unstable) return;
    _unstableReceiver = unstable;
    _initialized = false;
    await initialize();
  }

  void _onConnection(CastConnectionState state) {
    final wasCasting = _casting;
    _connection = state;
    _connectedDevice = _sender.connectedDevice;
    if (state == CastConnectionState.disconnected) {
      _connectedDevice = null;
      if (wasCasting) {
        // Reconnect, target disappearance, or failed handoff path: keep the
        // snapshot + last known position so retry/resume can proceed, and
        // surface explicit guidance instead of silently dropping.
        _fail(
          'Chromecast connection lost. Reconnect to resume where you left '
          'off, or resume on this iPhone.',
        );
      }
    }
    notifyListeners();
  }

  Future<void> connect(CastDevice device) => _guarded(() async {
    _error = null;
    notifyListeners();
    if (!_isSupported()) {
      throw const CastException(
        'Chromecast is available on iPhone and Android.',
      );
    }
    await initialize();
    await _sender.connect(device);
    await _waitForConnection();
    _connection = _sender.connectionState;
    _connectedDevice = _sender.connectedDevice ?? device;
    _lastDevice = device;
    notifyListeners();
    // Auto-handoff keeps the iPhone MVP to one tap: picking a target hands
    // off the current track at its current position. Calls the unguarded
    // core directly: castCurrent() would early-return on the shared busy
    // guard while this connect is still running.
    if (_playback.currentTrack != null && !_casting) {
      await _castCurrentNow();
    }
  });

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
  Future<void> castCurrent() => _guarded(_castCurrentNow);

  Future<void> _castCurrentNow() async {
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
    final queue = List<Track>.of(_playback.queue);
    final index =
        _playback.currentIndex ??
        queue.indexWhere((item) => item.id == track.id);
    final safeIndex = index < 0 ? 0 : index;
    final position = _playback.position;

    await _playback.stopForCast();
    _playback.setCastingActive(true);
    try {
      await _loadWithFallback(session, track, position, playlistItemId: null);
    } catch (_) {
      _playback.setCastingActive(false);
      rethrow;
    }
    _snapshot = queue.isEmpty ? [track] : queue;
    _remoteIndex = safeIndex.clamp(0, _snapshot.length - 1);
    _remoteTrack = track;
    _casting = true;
    _lastKnownPosition = position;
    _lastKnownPlaying = true;
    _error = null;
    notifyListeners();
  }

  Future<void> _loadWithFallback(
    JellyfinSession session,
    Track track,
    Duration position, {
    String? playlistItemId,
  }) async {
    try {
      final payload = _adapter.buildPayload(
        session,
        track,
        position: position,
        playlistItemId: playlistItemId,
      );
      await _sender.loadSingle(payload, position: payload.startPosition);
      _remote = _remote.copyWith(
        position: payload.startPosition,
        duration: payload.duration,
        playerState: CastPlayerState.playing,
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
      await _sender.loadSingle(fallback, position: fallback.startPosition);
      _remote = _remote.copyWith(
        position: fallback.startPosition,
        duration: fallback.duration,
        playerState: CastPlayerState.playing,
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
    _lastKnownPosition = safe;
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
      _lastKnownPosition = Duration.zero;
      return;
    }
    if (_snapshot.isEmpty) {
      await _sender.previous();
      return;
    }
    final at = _remoteIndex - 1;
    if (at < 0) {
      await _sender.seek(Duration.zero);
      _lastKnownPosition = Duration.zero;
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
      _lastKnownPosition = Duration.zero;
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
    );
    _remoteIndex = at;
    _remoteTrack = track;
    _lastKnownPosition = Duration.zero;
    _lastKnownPlaying = autoplay;
    notifyListeners();
  }

  /// Reconnects to the last target and reloads at the last known position.
  Future<void> retry() => _guarded(() async {
    final device = _lastDevice;
    final track = _remoteTrack;
    final session = _session;
    if (device == null || track == null || session == null) {
      throw const CastException(
        'Nothing to reconnect. Pick a Chromecast and try again.',
      );
    }
    await initialize();
    await _sender.connect(device);
    await _waitForConnection();
    _connection = _sender.connectionState;
    _connectedDevice = _sender.connectedDevice ?? device;
    await _loadWithFallback(
      session,
      track,
      _lastKnownPosition,
      playlistItemId: null,
    );
    if (!_lastKnownPlaying) await _sender.pause();
    _casting = true;
    _error = null;
    notifyListeners();
  });

  /// Ends the Cast session and resumes local playback where remote left off.
  ///
  /// Queue/history are preserved: resuming jumps the unchanged local queue
  /// to the remote index (recording history exactly as a local navigation
  /// would) and seeks to the remote position.
  Future<void> disconnect({bool resumeLocal = true}) => _guarded(() async {
    final position = _remote.position;
    final playing = _remote.isPlaying;
    final index = _remoteIndex;
    final hadRemote = _remoteTrack != null;
    await _sender.disconnect(stopReceiver: true);
    _connection = CastConnectionState.disconnected;
    _connectedDevice = null;
    _casting = false;
    _playback.setCastingActive(false);
    _error = null;
    notifyListeners();
    if (resumeLocal && hadRemote && _snapshot.isNotEmpty) {
      final at = index.clamp(0, _snapshot.length - 1);
      final current = _playback.currentIndex;
      if (current == null || current != at) {
        await _playback.playQueueIndex(at);
      }
      await _playback.seek(position);
      if (playing) {
        await _playback.play();
      } else {
        await _playback.pause();
      }
    } else if (resumeLocal && hadRemote) {
      await _playback.seek(position);
      if (playing) {
        await _playback.play();
      } else {
        await _playback.pause();
      }
    }
    _snapshot = const [];
    _remoteTrack = null;
    _remoteIndex = 0;
    notifyListeners();
  });

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
    notifyListeners();
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
    notifyListeners();
  }

  Future<void> _castGuarded(Future<void> Function() action) => _guarded(
    () async {
      if (!_casting) throw const CastException('Nothing is casting right now.');
      await action();
    },
  );

  Future<void> _guarded(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      await action();
    } on CastException catch (error) {
      _fail(error.message);
      rethrow;
    } catch (error) {
      final message = redactSecrets(error);
      _fail(message);
      throw CastException(message);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _fail(String message) {
    _error = message.isEmpty ? 'Chromecast request failed.' : message;
    notifyListeners();
  }

  @override
  void dispose() {
    _devicesSub?.cancel();
    _connectionSub?.cancel();
    _remoteSub?.cancel();
    super.dispose();
  }
}
