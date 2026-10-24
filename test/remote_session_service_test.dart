import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:spotifin/services/jellyfin/jellyfin_client.dart';
import 'package:spotifin/services/jellyfin/session.dart';
import 'package:spotifin/services/playback/remote_playback.dart';
import 'package:spotifin/services/playback/remote_session_service.dart';
import 'package:spotifin/storage/database.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _sessionA = JellyfinSession(
  serverUrl: 'https://music.example.com',
  serverId: 'server',
  deviceId: 'local-device',
  userId: 'user-a',
  userName: 'User A',
  accessToken: 'token-a',
);

const _sessionB = JellyfinSession(
  serverUrl: 'https://music.example.com',
  serverId: 'server',
  deviceId: 'local-device',
  userId: 'user-b',
  userName: 'User B',
  accessToken: 'token-b',
);

void main() {
  test('clear discards a pending refresh success', () async {
    final fetchStarted = Completer<void>();
    final response = Completer<http.Response>();
    final harness = _Harness((request) async {
      if (request.url.path.endsWith('/Capabilities/Full')) {
        return http.Response('', 204);
      }
      if (request.url.path.endsWith('/Sessions')) {
        fetchStarted.complete();
        return response.future;
      }
      return http.Response('', 404);
    });
    addTearDown(harness.dispose);
    var notifications = 0;
    harness.service.addListener(() => notifications++);

    final configure = harness.service.configure(_sessionA);
    await fetchStarted.future;
    await harness.service.clear();
    final notificationsAfterClear = notifications;
    response.complete(_sessionsResponse('old-device', 'user-a'));
    await configure;

    expect(harness.service.sessions, isEmpty);
    expect(harness.service.error, isNull);
    expect(notifications, notificationsAfterClear);
  });

  test('clear discards a pending refresh failure', () async {
    final fetchStarted = Completer<void>();
    final response = Completer<http.Response>();
    final harness = _Harness((request) async {
      if (request.url.path.endsWith('/Capabilities/Full')) {
        return http.Response('', 204);
      }
      if (request.url.path.endsWith('/Sessions')) {
        fetchStarted.complete();
        return response.future;
      }
      return http.Response('', 404);
    });
    addTearDown(harness.dispose);
    var notifications = 0;
    harness.service.addListener(() => notifications++);

    final configure = harness.service.configure(_sessionA);
    await fetchStarted.future;
    await harness.service.clear();
    final notificationsAfterClear = notifications;
    response.complete(http.Response('server error', 500));
    await configure;

    expect(harness.service.sessions, isEmpty);
    expect(harness.service.error, isNull);
    expect(notifications, notificationsAfterClear);
  });

  test('dispose discards a pending refresh without notifying', () async {
    final fetchStarted = Completer<void>();
    final response = Completer<http.Response>();
    var fetchCount = 0;
    final harness = _Harness((request) async {
      if (request.url.path.endsWith('/Capabilities/Full')) {
        return http.Response('', 204);
      }
      if (request.url.path.endsWith('/Sessions')) {
        fetchCount++;
        if (fetchCount == 1) {
          return _sessionsResponse('existing-device', 'user-a');
        }
        fetchStarted.complete();
        return response.future;
      }
      return http.Response('', 404);
    });
    addTearDown(() => harness.dispose(serviceDisposed: true));
    var notifications = 0;
    harness.service.addListener(() => notifications++);

    await harness.service.configure(_sessionA);
    await harness.socket.sessionsStartSent.future;
    final refresh = harness.service.refresh();
    await fetchStarted.future;
    harness.service.dispose();
    final notificationsAfterDispose = notifications;
    response.complete(http.Response('server error', 500));
    await refresh;

    expect(harness.service.sessions.single.id, 'existing-device');
    expect(harness.service.error, isNull);
    expect(notifications, notificationsAfterDispose);
  });

  test('reconfigure keeps late account A results out of account B', () async {
    final accountAFetchStarted = Completer<void>();
    final accountAResponse = Completer<http.Response>();
    final harness = _Harness((request) async {
      if (request.url.path.endsWith('/Capabilities/Full')) {
        return http.Response('', 204);
      }
      if (request.url.path.endsWith('/Sessions')) {
        if (request.headers['X-Emby-Token'] == 'token-a') {
          accountAFetchStarted.complete();
          return accountAResponse.future;
        }
        return _sessionsResponse('account-b-device', 'user-b');
      }
      return http.Response('', 404);
    });
    addTearDown(harness.dispose);
    var notifications = 0;
    harness.service.addListener(() => notifications++);

    final configureA = harness.service.configure(_sessionA);
    await accountAFetchStarted.future;
    await harness.service.configure(_sessionB);
    await harness.socket.sessionsStartSent.future;
    expect(harness.service.sessions.single.id, 'account-b-device');
    final notificationsAfterB = notifications;

    accountAResponse.complete(_sessionsResponse('account-a-device', 'user-a'));
    await configureA;

    expect(harness.service.sessions.single.id, 'account-b-device');
    expect(harness.service.error, isNull);
    expect(notifications, notificationsAfterB);
    expect(harness.socketConnections, 1);
  });

  test('configure discards an old account capability error', () async {
    final accountAAdvertiseStarted = Completer<void>();
    final accountAAdvertiseResponse = Completer<http.Response>();
    final harness = _Harness((request) async {
      if (request.url.path.endsWith('/Capabilities/Full')) {
        if (request.headers['X-Emby-Token'] == 'token-a') {
          accountAAdvertiseStarted.complete();
          return accountAAdvertiseResponse.future;
        }
        return http.Response('', 204);
      }
      if (request.url.path.endsWith('/Sessions')) {
        return _sessionsResponse('account-b-device', 'user-b');
      }
      return http.Response('', 404);
    });
    addTearDown(harness.dispose);
    var notifications = 0;
    harness.service.addListener(() => notifications++);

    final configureA = harness.service.configure(_sessionA);
    await accountAAdvertiseStarted.future;
    await harness.service.configure(_sessionB);
    await harness.socket.sessionsStartSent.future;
    expect(harness.service.sessions.single.id, 'account-b-device');
    final notificationsAfterB = notifications;

    accountAAdvertiseResponse.complete(http.Response('server error', 500));
    await configureA;

    expect(harness.service.sessions.single.id, 'account-b-device');
    expect(harness.service.error, isNull);
    expect(notifications, notificationsAfterB);
    expect(harness.socketConnections, 1);
  });

  test('a fresh same-account refresh publishes its result', () async {
    final refreshStarted = Completer<void>();
    final response = Completer<http.Response>();
    var fetchCount = 0;
    final harness = _Harness((request) async {
      if (request.url.path.endsWith('/Capabilities/Full')) {
        return http.Response('', 204);
      }
      if (request.url.path.endsWith('/Sessions')) {
        fetchCount++;
        if (fetchCount == 1) {
          return _sessionsResponse('initial-device', 'user-a');
        }
        refreshStarted.complete();
        return response.future;
      }
      return http.Response('', 404);
    });
    addTearDown(harness.dispose);
    var notifications = 0;
    harness.service.addListener(() => notifications++);

    await harness.service.configure(_sessionA);
    expect(harness.service.sessions.single.id, 'initial-device');
    final notificationsBeforeRefresh = notifications;
    final refresh = harness.service.refresh();
    await refreshStarted.future;
    response.complete(_sessionsResponse('refreshed-device', 'user-a'));
    await refresh;

    expect(harness.service.sessions.single.id, 'refreshed-device');
    expect(harness.service.error, isNull);
    expect(notifications, greaterThan(notificationsBeforeRefresh));
  });

  test(
    'queued socket work and late command errors are discarded on clear',
    () async {
      final playback = _FakePlayback()
        ..volumeStarted = Completer<void>()
        ..volumeGate = Completer<void>()
        ..volumeFinished = Completer<void>()
        ..failVolumeAfterGate = true;
      final harness = _Harness((request) async {
        if (request.url.path.endsWith('/Capabilities/Full')) {
          return http.Response('', 204);
        }
        if (request.url.path.endsWith('/Sessions')) {
          return http.Response('[]', 200);
        }
        return http.Response('', 404);
      }, playback: playback);
      addTearDown(harness.dispose);
      var notifications = 0;
      harness.service.addListener(() => notifications++);

      await harness.service.configure(_sessionA);
      await harness.socket.sessionsStartSent.future;
      harness.socket.send('GeneralCommand', {
        'Name': 'SetVolume',
        'Arguments': {'Volume': '45'},
      });
      await playback.volumeStarted!.future;
      harness.socket.send('GeneralCommand', {
        'Name': 'SetShuffleQueue',
        'Arguments': {'ShuffleMode': 'Shuffle'},
      });

      await harness.service.clear();
      final notificationsAfterClear = notifications;
      playback.volumeGate!.completeError(StateError('old account failure'));
      await playback.volumeFinished!.future;
      await Future<void>.delayed(Duration.zero);

      expect(playback.volumeCalls, 1);
      expect(playback.shuffleCalls, 0);
      expect(harness.service.error, isNull);
      expect(notifications, notificationsAfterClear);
    },
  );
}

class _Harness {
  _Harness(
    Future<http.Response> Function(http.Request) handler, {
    _FakePlayback? playback,
  }) : httpClient = MockClient(handler),
       database = AppDatabase.forTesting(NativeDatabase.memory()),
       socket = _FakeSocket(),
       playback = playback ?? _FakePlayback() {
    client = JellyfinClient(httpClient: httpClient);
    service = RemoteSessionService(
      client,
      this.playback,
      database,
      socketConnector: (_) {
        socketConnections++;
        return socket.channel;
      },
    );
  }

  final MockClient httpClient;
  final AppDatabase database;
  final _FakeSocket socket;
  final _FakePlayback playback;
  int socketConnections = 0;
  late final JellyfinClient client;
  late final RemoteSessionService service;

  Future<void> dispose({bool serviceDisposed = false}) async {
    if (!serviceDisposed) await service.clear();
    socket.incoming.close();
    httpClient.close();
    await database.close();
  }
}

class _MockWebSocketChannel extends Mock implements WebSocketChannel {}

class _MockWebSocketSink extends Mock implements WebSocketSink {}

class _FakeSocket {
  _FakeSocket() {
    when(() => channel.ready).thenAnswer((_) async {});
    when(() => channel.stream).thenAnswer((_) => incoming.stream);
    when(() => channel.sink).thenReturn(sink);
    when(() => sink.add(any())).thenAnswer((invocation) {
      final payload = jsonDecode(
        invocation.positionalArguments.single as String,
      ) as Map<String, dynamic>;
      if (payload['MessageType'] == 'SessionsStart' &&
          !sessionsStartSent.isCompleted) {
        sessionsStartSent.complete();
      }
    });
    when(() => sink.close(1001)).thenAnswer((_) async {});
  }

  final incoming = StreamController<Object?>(sync: true);
  final channel = _MockWebSocketChannel();
  final sink = _MockWebSocketSink();
  final sessionsStartSent = Completer<void>();

  void send(String type, Map<String, dynamic> data) {
    incoming.add(jsonEncode({'MessageType': type, 'Data': data}));
  }
}

class _FakePlayback implements RemotePlayback {
  Completer<void>? volumeStarted;
  Completer<void>? volumeGate;
  Completer<void>? volumeFinished;
  bool failVolumeAfterGate = false;
  int volumeCalls = 0;
  int shuffleCalls = 0;

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
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setRepeatMode(LoopMode mode) async {}

  @override
  Future<void> setShuffle(bool enabled) async {
    shuffleCalls++;
  }

  @override
  Future<void> setVolume(double volume) async {
    volumeCalls++;
    if (volumeStarted case final started?) {
      started.complete();
    }
    try {
      if (volumeGate case final gate?) await gate.future;
      if (failVolumeAfterGate) throw StateError('old account failure');
    } finally {
      if (volumeFinished case final finished?) finished.complete();
    }
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> takeOver(
    List<Track> tracks, {
    required int startIndex,
    required Duration position,
  }) async {}

  @override
  Future<void> toggle() async {}
}

http.Response _sessionsResponse(String id, String userId) => http.Response(
  jsonEncode([
    {
      'Id': id,
      'UserId': userId,
      'Client': 'Spotifin',
      'DeviceId': 'other-device',
      'DeviceName': 'Other device',
      'SupportsMediaControl': true,
      'IsActive': true,
    },
  ]),
  200,
);
