import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:spotifin/platform/playback_state_store.dart';
import 'package:spotifin/services/downloads/download_service.dart';
import 'package:spotifin/services/jellyfin/jellyfin_client.dart';
import 'package:spotifin/services/jellyfin/session.dart';
import 'package:spotifin/services/playback/playback_service.dart';
import 'package:spotifin/storage/database.dart';

/// Recorded Jellyfin playback report (endpoint + decoded JSON body).
class RecordedReport {
  RecordedReport({required this.endpoint, required this.body});

  final String endpoint;
  final Map<String, dynamic> body;
}

/// Controlled [AudioPlayer] test double.
///
/// Records every audio operation applied by [PlaybackService] and exposes
/// broadcast streams plus explicit emitters so tests drive events without
/// native audio. It never implements queue policy: it stores the sources it
/// is given and tracks a current index, position, and flags supplied by the
/// test. [sequenceState] intentionally returns an empty sequence (no tag) so
/// the service uses its current-index fallback.
class FakeAudioPlayer extends Mock implements AudioPlayer {
  final List<AudioSource> sources = [];
  int? _currentIndex;
  bool _playing = false;
  Duration _position = Duration.zero;
  LoopMode _loopMode = LoopMode.off;
  bool _shuffleEnabled = false;
  double _volume = 1;
  bool _disposed = false;

  final StreamController<PlayerState> _playerStateController =
      StreamController<PlayerState>.broadcast();
  final StreamController<int?> _currentIndexController =
      StreamController<int?>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<bool> _shuffleController =
      StreamController<bool>.broadcast();

  /// Operation names in call order (for example `setAudioSources`, `seek`).
  final List<String> calls = [];

  /// Seek history: requested positions and indices.
  final List<Duration?> seekPositions = [];
  final List<int?> seekIndices = [];

  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  int disposeCalls = 0;

  List<AudioSource>? lastSetSources;
  int? lastSetInitialIndex;
  Duration? lastSetInitialPosition;

  /// When set, [setAudioSources] waits for this gate before completing.
  Completer<void>? loadGate;

  /// When set, [seek]/[seekToNext]/[seekToPrevious] wait for this gate.
  Completer<void>? seekGate;

  /// When set, [setAudioSources] throws this error instead of completing.
  Object? loadError;

  /// When set, seek operations throw this error instead of completing.
  Object? seekError;

  @override
  Stream<PlayerState> get playerStateStream => _playerStateController.stream;

  @override
  Stream<int?> get currentIndexStream => _currentIndexController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<bool> get shuffleModeEnabledStream => _shuffleController.stream;

  @override
  bool get playing => _playing;

  @override
  Duration get position => _position;

  @override
  int? get currentIndex => _currentIndex;

  @override
  LoopMode get loopMode => _loopMode;

  @override
  bool get shuffleModeEnabled => _shuffleEnabled;

  double get lastVolume => _volume;

  bool get isDisposed => _disposed;

  @override
  SequenceState get sequenceState => SequenceState(
    sequence: const [],
    currentIndex: null,
    shuffleIndices: const [],
    shuffleModeEnabled: _shuffleEnabled,
    loopMode: _loopMode,
  );

  /// Emit a current-index event as if the player advanced.
  void emitIndex(int? index) {
    _currentIndex = index;
    if (!_currentIndexController.isClosed) {
      _currentIndexController.add(index);
    }
  }

  /// Emit a position event as if playback progressed.
  void emitPosition(Duration position) {
    _position = position;
    if (!_positionController.isClosed) {
      _positionController.add(position);
    }
  }

  /// Emit a completed player state as if the queue finished.
  void emitCompletion() {
    if (!_playerStateController.isClosed) {
      _playerStateController.add(PlayerState(false, ProcessingState.completed));
    }
  }

  /// Emit a shuffle-mode event as if the platform toggled shuffle.
  void emitShuffle(bool enabled) {
    _shuffleEnabled = enabled;
    if (!_shuffleController.isClosed) {
      _shuffleController.add(enabled);
    }
  }

  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> audioSources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) async {
    calls.add('setAudioSources');
    lastSetSources = List.of(audioSources);
    lastSetInitialIndex = initialIndex;
    lastSetInitialPosition = initialPosition;
    final error = loadError;
    if (error != null) throw error;
    final gate = loadGate;
    if (gate != null) await gate.future;
    sources
      ..clear()
      ..addAll(audioSources);
    _currentIndex = initialIndex;
    if (initialPosition != null) _position = initialPosition;
    return null;
  }

  @override
  Future<void> clearAudioSources() async {
    calls.add('clearAudioSources');
    sources.clear();
  }

  @override
  Future<void> addAudioSource(AudioSource audioSource) async {
    calls.add('addAudioSource');
    sources.add(audioSource);
  }

  @override
  Future<void> addAudioSources(List<AudioSource> audioSources) async {
    calls.add('addAudioSources');
    sources.addAll(audioSources);
  }

  @override
  Future<void> insertAudioSources(
    int index,
    List<AudioSource> audioSources,
  ) async {
    calls.add('insertAudioSources');
    sources.insertAll(index.clamp(0, sources.length), audioSources);
  }

  @override
  Future<void> removeAudioSourceAt(int index) async {
    calls.add('removeAudioSourceAt');
    if (index >= 0 && index < sources.length) {
      sources.removeAt(index);
    }
    if (_currentIndex != null && sources.isEmpty) {
      _currentIndex = null;
    } else if (_currentIndex != null && _currentIndex! >= sources.length) {
      _currentIndex = sources.length - 1;
    }
  }

  @override
  Future<void> moveAudioSource(int currentIndex, int newIndex) async {
    calls.add('moveAudioSource');
    if (currentIndex < 0 ||
        currentIndex >= sources.length ||
        newIndex < 0 ||
        newIndex >= sources.length) {
      return;
    }
    final item = sources.removeAt(currentIndex);
    sources.insert(newIndex, item);
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    calls.add('seek');
    seekPositions.add(position);
    seekIndices.add(index);
    final error = seekError;
    if (error != null) throw error;
    final gate = seekGate;
    if (gate != null) await gate.future;
    if (position != null) _position = position;
    if (index != null) _currentIndex = index;
  }

  @override
  Future<void> seekToNext() async {
    calls.add('seekToNext');
    final error = seekError;
    if (error != null) throw error;
    final gate = seekGate;
    if (gate != null) await gate.future;
    if (_currentIndex != null && _currentIndex! + 1 < sources.length) {
      _currentIndex = _currentIndex! + 1;
      _position = Duration.zero;
    }
  }

  @override
  Future<void> seekToPrevious() async {
    calls.add('seekToPrevious');
    final error = seekError;
    if (error != null) throw error;
    final gate = seekGate;
    if (gate != null) await gate.future;
    if (_currentIndex != null && _currentIndex! - 1 >= 0) {
      _currentIndex = _currentIndex! - 1;
      _position = Duration.zero;
    }
  }

  @override
  Future<void> play() async {
    calls.add('play');
    playCalls++;
    _playing = true;
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    pauseCalls++;
    _playing = false;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    stopCalls++;
    _playing = false;
  }

  @override
  Future<void> setVolume(double volume) async {
    calls.add('setVolume');
    _volume = volume;
  }

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {
    calls.add('setShuffleModeEnabled');
    _shuffleEnabled = enabled;
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {
    calls.add('setLoopMode');
    _loopMode = mode;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    calls.add('dispose');
    disposeCalls++;
    _disposed = true;
    await _playerStateController.close();
    await _currentIndexController.close();
    await _positionController.close();
    await _shuffleController.close();
  }
}

/// In-memory [PlaybackStateStore] with per-account values and write records.
class FakePlaybackStateStore extends PlaybackStateStore {
  final Map<String, String> values = {};
  final List<String> reads = [];
  final List<RecordedWrite> writes = [];
  final List<String> clears = [];

  void seed(String accountId, String value) {
    values[accountId] = value;
  }

  @override
  Future<String?> read(String accountId) async {
    reads.add(accountId);
    return values[accountId];
  }

  @override
  Future<void> write(String accountId, String value) async {
    values[accountId] = value;
    writes.add(RecordedWrite(accountId, value));
  }

  @override
  Future<void> clear(String accountId) async {
    values.remove(accountId);
    clears.add(accountId);
  }
}

/// A single state-store write record.
class RecordedWrite {
  RecordedWrite(this.accountId, this.value);

  final String accountId;
  final String value;
}

class _MockDownloadService extends Mock implements DownloadService {}

/// Controlled harness for testing the real [PlaybackService] without native
/// audio or a live server.
///
/// The fake player records applied audio operations and exposes events; it
/// never implements queue policy. Downloads resolve to no local files by
/// default. The [JellyfinClient] uses a [MockClient] that records playback
/// report bodies and answers `204` without network access.
class PlaybackHarness {
  PlaybackHarness({math.Random? random, Map<String, Uri>? localFiles})
    : random = random ?? math.Random(42) {
    player = FakeAudioPlayer();
    stateStore = FakePlaybackStateStore();
    downloads = _MockDownloadService();
    _localFiles = Map.of(localFiles ?? const {});
    registerFallbackValue(<String>[]);
    when(() => downloads.resolveAll(any()))
        .thenAnswer((_) async => Map<String, Uri>.of(_localFiles));
    client = JellyfinClient(
      httpClient: MockClient((http.Request request) async {
        final endpoint = request.url.path;
        Map<String, dynamic> body = const {};
        if (request.body.isNotEmpty) {
          try {
            body = jsonDecode(request.body) as Map<String, dynamic>;
          } catch (_) {
            body = const {};
          }
        }
        reports.add(RecordedReport(endpoint: endpoint, body: body));
        return http.Response('', 204);
      }),
    );
    service = PlaybackService(
      client,
      downloads,
      player: player,
      stateStore: stateStore,
      configureAudioSession: () async {},
      random: this.random,
    );
  }

  static const session = JellyfinSession(
    serverUrl: 'https://example.com',
    serverId: 'server',
    deviceId: 'device',
    userId: 'user',
    userName: 'Pablo',
    accessToken: 'token',
  );

  static String get accountId => '${session.serverId}.${session.userId}';

  final math.Random random;
  late final FakeAudioPlayer player;
  late final FakePlaybackStateStore stateStore;
  late final DownloadService downloads;
  late final JellyfinClient client;
  late final PlaybackService service;
  final List<RecordedReport> reports = [];
  late final Map<String, Uri> _localFiles;

  /// Local files returned by the downloads resolver (empty by default).
  Map<String, Uri> get localFiles => _localFiles;

  /// Configures the service session with an async no-op audio session.
  Future<void> configure() => service.configure(session);

  /// Yields to the event loop so serialized reports and stream events flush.
  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }

  /// Waits until at least [count] reports arrive or [timeout] elapses.
  Future<void> waitForReports(
    int count, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (reports.length < count && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// Reports filtered by Jellyfin endpoint suffix.
  List<RecordedReport> reportsFor(String suffix) =>
      reports.where((report) => report.endpoint.endsWith(suffix)).toList();

  /// Awaits pending fake operations, then disposes the subject and clients.
  ///
  /// Tests must call this (or otherwise close every stream/client) so no
  /// broadcast controller or HTTP client leaks between tests.
  Future<void> dispose() async {
    await settle();
    try {
      service.dispose();
    } catch (_) {}
    await settle();
    client.close();
    try {
      downloads.dispose();
    } catch (_) {}
  }
}

/// Builds a deterministic library track fixture.
Track playbackTrack(int index) => Track(
  id: 'track-$index',
  name: 'Song $index',
  album: 'Album',
  artist: 'Artist',
  artistItems: '[]',
  labels: '[]',
  durationTicks: 1800000000,
  favorite: false,
  playCount: 0,
  normalizationGain: null,
  albumNormalizationGain: null,
  container: 'mp3',
);

/// Builds [count] deterministic tracks with ids `track-0` … `track-N`.
List<Track> playbackCatalog(int count) => [
  for (var i = 0; i < count; i++) playbackTrack(i),
];
