import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:spotifin/services/jellyfin/jellyfin_client.dart';
import 'package:spotifin/services/jellyfin/remote_session.dart';
import 'package:spotifin/services/jellyfin/session.dart';
import 'package:spotifin/services/playback/playback_handoff.dart';
import 'package:spotifin/services/playback/remote_command_handler.dart';
import 'package:spotifin/services/playback/remote_playback.dart';
import 'package:spotifin/storage/database.dart';

void main() {
  test('maps playstate and general commands', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final playback = _FakePlayback();
    final handler = RemoteCommandHandler(playback, database);

    await handler.handle('Playstate', {
      'Command': 'Seek',
      'SeekPositionTicks': 90000000,
    });
    await handler.handle('GeneralCommand', {
      'Name': 'SetVolume',
      'Arguments': {'Volume': '42'},
    });
    await handler.handle('GeneralCommand', {
      'Name': 'SetRepeatMode',
      'Arguments': {'RepeatMode': 'RepeatOne'},
    });

    expect(playback.position, const Duration(seconds: 9));
    expect(playback.volume, .42);
    expect(playback.repeatMode, LoopMode.one);
  });

  test('preserves order and recalculates the start index', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.upsertTracks([
      TracksCompanion.insert(id: 'first', name: 'First'),
      TracksCompanion.insert(id: 'current', name: 'Current'),
    ]);
    final playback = _FakePlayback();
    final handler = RemoteCommandHandler(playback, database);

    await handler.handle('Play', {
      'PlayCommand': 'PlayNow',
      'ItemIds': ['missing', 'first', 'current'],
      'StartIndex': 2,
      'StartPositionTicks': 40000000,
    });

    expect(playback.takenOverTracks.map((track) => track.id), [
      'first',
      'current',
    ]);
    expect(playback.startIndex, 1);
    expect(playback.position, const Duration(seconds: 4));
  });

  test('starts locally before stopping an unchanged source', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.upsertTracks([
      TracksCompanion.insert(id: 'first', name: 'First'),
      TracksCompanion.insert(id: 'current', name: 'Current'),
    ]);
    final playback = _FakePlayback();
    final source = _remoteSession();
    final client = _FakeJellyfinClient([source], playback);
    addTearDown(client.close);
    final handoff = PlaybackHandoff(client, playback, database);

    await handoff.takeOver(_session, source);

    expect(playback.takenOverTracks.map((track) => track.id), [
      'first',
      'current',
    ]);
    expect(playback.startIndex, 1);
    expect(client.stoppedSessionId, 'remote');
    expect(client.stoppedAfterLocalStart, isTrue);
  });

  test(
    'does not stop the source when its current song is unavailable',
    () async {
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final playback = _FakePlayback();
      final source = _remoteSession();
      final client = _FakeJellyfinClient([source], playback);
      addTearDown(client.close);
      final handoff = PlaybackHandoff(client, playback, database);

      await expectLater(
        handoff.takeOver(_session, source),
        throwsA(isA<JellyfinException>()),
      );

      expect(playback.started, isFalse);
      expect(client.stoppedSessionId, isNull);
    },
  );
}

class _FakePlayback implements RemotePlayback {
  Duration? position;
  double? volume;
  LoopMode? repeatMode;
  List<Track> takenOverTracks = const [];
  int? startIndex;

  @override
  Future<void> seek(Duration position) async => this.position = position;

  @override
  Future<void> setVolume(double volume) async => this.volume = volume;

  @override
  Future<void> setRepeatMode(LoopMode mode) async => repeatMode = mode;

  @override
  Future<void> takeOver(
    List<Track> tracks, {
    required int startIndex,
    required Duration position,
  }) async {
    takenOverTracks = tracks;
    this.startIndex = startIndex;
    this.position = position;
    started = true;
  }

  @override
  Future<void> addNextToQueue(List<Track> tracks) async {}

  @override
  Future<void> addToQueue(Track track) async {}

  @override
  Future<void> next() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> previous() async {}

  @override
  Future<void> setShuffle(bool enabled) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> toggle() async {}

  bool started = false;
}

class _FakeJellyfinClient extends JellyfinClient {
  _FakeJellyfinClient(this.sessions, this.playback)
    : super(httpClient: http.Client());

  final List<RemoteSession> sessions;
  final _FakePlayback playback;
  String? stoppedSessionId;
  bool stoppedAfterLocalStart = false;

  @override
  Future<List<RemoteSession>> fetchSessions(JellyfinSession session) async =>
      sessions;

  @override
  Future<void> sendPlaystateCommand(
    JellyfinSession session,
    String sessionId,
    String command, {
    Duration? position,
  }) async {
    stoppedSessionId = sessionId;
    stoppedAfterLocalStart = playback.started;
  }
}

RemoteSession _remoteSession() => const RemoteSession(
  id: 'remote',
  userId: 'user',
  client: 'Spotifin',
  deviceId: 'mac',
  deviceName: 'Spotifin on macOS',
  supportsMediaControl: true,
  isActive: true,
  nowPlayingItemId: 'current',
  nowPlayingItemName: 'Current',
  playlistItemId: 'current-entry',
  position: Duration(seconds: 5),
  duration: Duration(minutes: 3),
  paused: false,
  canSeek: true,
  volume: 100,
  repeatMode: 'RepeatNone',
  shuffle: false,
  queue: [
    RemoteQueueItem(itemId: 'missing', playlistItemId: 'missing-entry'),
    RemoteQueueItem(itemId: 'first', playlistItemId: 'first-entry'),
    RemoteQueueItem(itemId: 'current', playlistItemId: 'current-entry'),
  ],
);

const _session = JellyfinSession(
  serverUrl: 'https://example.com',
  serverId: 'server',
  deviceId: 'phone',
  userId: 'user',
  userName: 'Pablo',
  accessToken: 'token',
);
