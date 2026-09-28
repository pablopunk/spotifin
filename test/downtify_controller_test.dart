import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotifin/app/providers.dart';
import 'package:spotifin/app/state/app_controller.dart';
import 'package:spotifin/app/state/downtify_controller.dart';
import 'package:spotifin/services/downtify/downtify_client.dart';
import 'package:spotifin/services/downtify/downtify_models.dart';
import 'package:spotifin/services/jellyfin/jellyfin_client.dart';
import 'package:spotifin/services/jellyfin/session.dart';
import 'package:spotifin/storage/database.dart';

import 'support/manual_import_scheduler.dart';

const _session = JellyfinSession(
  serverUrl: 'https://jellyfin.example.com',
  serverId: 'server',
  deviceId: 'device',
  userId: 'user',
  userName: 'Pablo',
  accessToken: 'token',
);

const _origin = 'https://downtify.example.com';

Future<void> settle() async {
  for (var i = 0; i < 50; i++) {
    await Future(() {});
  }
}

Map<String, dynamic> _songJson(String id, String name) => {
  'song_id': id,
  'name': name,
  'artists': ['Artist'],
};

Map<String, dynamic> _jobJson(
  String songId,
  String status, {
  double progress = 0,
  String message = '',
  String? filename,
}) => {
  'song': {
    'song_id': songId,
    'name': 'Song $songId',
    'artists': ['Artist'],
  },
  'status': status,
  'progress': progress,
  'message': message,
  'filename': filename,
};

Future<void> _seedImport(
  AppDatabase database, {
  required String id,
  required String status,
  String externalSongId = 'external',
  String? jobId,
  String origin = _origin,
  int retryCount = 0,
  bool messageShown = false,
  DateTime? createdAt,
  String serverId = 'server',
  String userId = 'user',
}) async {
  final now = createdAt ?? DateTime(2026, 1, 1);
  await database.putDowntifyImport(
    DowntifyImportsCompanion.insert(
      id: id,
      jellyfinServerId: serverId,
      jellyfinUserId: userId,
      downtifyUrl: origin,
      externalSongId: externalSongId,
      jobId: Value(jobId),
      songJson: jsonEncode(_songJson(externalSongId, 'Song $externalSongId')),
      status: status,
      retryCount: Value(retryCount),
      messageShown: Value(messageShown),
      createdAt: now,
      updatedAt: now,
    ),
  );
}

class _Harness {
  _Harness({
    required this.queueResponses,
    this.scanStatus = 204,
    this.tracks = const [],
    this.tracksStatus = 200,
    this.deleteRemoved = true,
    this.onDowntifyRequest,
  }) : sent = [],
       scheduler = ManualImportScheduler() {
    downtifyClient = DowntifyClient(
      httpClient: MockClient((request) async {
        final path = request.url.path;
        sent.add('${request.method} $path');
        final hook = onDowntifyRequest;
        if (hook != null) {
          final hooked = await hook(request);
          if (hooked != null) return hooked;
        }
        if (path == '/api/version') {
          final gate = versionGate;
          versionGate = null;
          if (gate != null) await gate.future;
          return http.Response(jsonEncode('2.10.2'), 200);
        }
        if (path == '/api/download/batch') {
          final gate = batchGate;
          if (gate != null) await gate.future;
          return http.Response(
            jsonEncode({
              'job_ids': ['job-new'],
              'count': 1,
            }),
            200,
          );
        }
        if (path == '/api/queue') {
          final gate = queueGate;
          if (gate != null) await gate.future;
          final next = queueResponses.isEmpty
              ? <Object>[]
              : queueResponses.removeAt(0);
          if (next is Exception) throw next;
          return http.Response(jsonEncode(next), 200);
        }
        if (request.method == 'DELETE') {
          return http.Response(jsonEncode({'removed': deleteRemoved}), 200);
        }
        return http.Response(jsonEncode(<Object>[]), 200);
      }),
    );
    jellyfinClient = JellyfinClient(
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path == '/Library/Refresh') {
          final gate = scanGate;
          if (gate != null) await gate.future;
          scanRequests++;
          if (scanStatus != 204) {
            return http.Response('denied', scanStatus);
          }
          return http.Response('', 204);
        }
        if (request.method == 'GET' &&
            path.endsWith('/Items') &&
            request.url.queryParameters['IncludeItemTypes'] == 'Audio') {
          if (tracksStatus != 200) {
            return http.Response('boom', tracksStatus);
          }
          return http.Response(
            jsonEncode({'Items': tracks, 'TotalRecordCount': tracks.length}),
            200,
          );
        }
        return http.Response('', 204);
      }),
    );
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        downtifyClientProvider.overrideWithValue(downtifyClient),
        jellyfinClientProvider.overrideWithValue(jellyfinClient),
        appControllerProvider.overrideWith(_AuthenticatedAppController.new),
        importSchedulerProvider.overrideWithValue(scheduler),
      ],
    );
  }

  final List<Object> queueResponses;
  final int scanStatus;
  final List<Map<String, dynamic>> tracks;
  final int tracksStatus;
  final bool deleteRemoved;
  final List<String> sent;
  final ManualImportScheduler scheduler;
  late final DowntifyClient downtifyClient;
  late final JellyfinClient jellyfinClient;
  late final ProviderContainer container;

  AppDatabase database = AppDatabase.forTesting(NativeDatabase.memory());
  Completer<void>? queueGate;
  Completer<void>? batchGate;
  Completer<void>? scanGate;
  Completer<void>? versionGate;
  int scanRequests = 0;
  Future<http.Response?> Function(http.BaseRequest request)? onDowntifyRequest;

  DowntifyController get controller =>
      container.read(downtifyControllerProvider.notifier);

  DowntifyState get state => container.read(downtifyControllerProvider);

  Future<void> start() async {
    final subscription = container.listen(
      downtifyControllerProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    // Let initialization finish (consuming one queue read) before the
    // account activates, so recovery reads follow in a fixed order.
    await settle();
    container.read(accountScopeProvider).activate(_session);
    await settle();
  }

  Future<void> dispose() async {
    container.dispose();
    downtifyClient.close();
    jellyfinClient.close();
    await database.close();
  }
}

DowntifySong _song(String id, String name) => DowntifySong.fromJson({
  'song_id': id,
  'name': name,
  'artists': ['Artist'],
});

void main() {
  test('moves a queued song through download, scan, and import', () async {
    SharedPreferences.setMockInitialValues({'downtifyServerUrl': _origin});
    final harness = _Harness(
      queueResponses: [
        <Object>[],
        <Object>[],
        [_jobJson('external', 'downloading', progress: 40)],
        [
          _jobJson(
            'external',
            'done',
            progress: 100,
            filename: 'Artist - Song.mp3',
          ),
        ],
      ],
      tracks: [
        {
          'Id': 'jellyfin-track',
          'Name': 'Imported Song',
          'Artists': ['Artist'],
        },
      ],
    );
    addTearDown(harness.dispose);
    await harness.start();

    await harness.controller.enqueue(_song('external', 'Imported Song'));
    expect(harness.state.imports.single.status, 'downloading');

    await harness.controller.poll();
    expect(harness.state.imports.single.status, 'requestingScan');
    await harness.scheduler.advance(const Duration(seconds: 1));
    await settle();
    expect(harness.scanRequests, 1);
    expect(harness.state.imports.single.status, 'waitingForJellyfin');

    await harness.controller.poll();
    await settle();
    expect(harness.state.imports.single.status, 'imported');
    expect(harness.state.imports.single.matchedTrackId, 'jellyfin-track');
    expect(harness.state.notices.single.message, contains('available'));
  });

  test('recovers polling after a transient queue failure', () async {
    SharedPreferences.setMockInitialValues({});
    var failing = true;
    final harness = _Harness(
      queueResponses: [<Object>[]],
      onDowntifyRequest: (request) async {
        if (request.url.path == '/api/queue' && failing) {
          throw Exception('boom');
        }
        return null;
      },
    );
    addTearDown(harness.dispose);
    await harness.start();

    await harness.controller.configure(_origin);
    await harness.controller.poll();
    expect(harness.state.availability, DowntifyAvailability.unavailable);

    failing = false;
    await harness.controller.poll();
    expect(harness.state.availability, DowntifyAvailability.available);
  });

  test('retries a failed download three times and reports it once', () async {
    SharedPreferences.setMockInitialValues({'downtifyServerUrl': _origin});
    final harness = _Harness(
      queueResponses: [
        [_jobJson('external', 'error', message: 'No match')],
        [_jobJson('external', 'error', message: 'No match')],
        [_jobJson('external', 'error', message: 'No match')],
        [_jobJson('external', 'error', message: 'No match')],
        [_jobJson('external', 'error', message: 'No match')],
        [_jobJson('external', 'error', message: 'No match')],
      ],
    );
    addTearDown(harness.dispose);
    await harness.start();

    await harness.controller.enqueue(_song('external', 'Broken Song'));
    await harness.controller.poll();
    await harness.controller.poll();
    await harness.controller.poll();
    await harness.controller.poll();
    await settle();

    final state = harness.state;
    expect(
      harness.sent.where((call) => call.contains('/api/download/batch')),
      hasLength(4),
    );
    expect(state.imports.single.retryCount, 3);
    expect(state.imports.single.status, 'downloadFailed');
    expect(state.notices, hasLength(1));

    await harness.controller.poll();
    await settle();
    expect(harness.state.notices, hasLength(1));
    expect(
      harness.sent.where((call) => call.contains('/api/download/batch')),
      hasLength(4),
    );
  });

  test('removes a queued download remotely and locally', () async {
    SharedPreferences.setMockInitialValues({'downtifyServerUrl': _origin});
    final harness = _Harness(queueResponses: []);
    addTearDown(harness.dispose);
    await _seedImport(
      harness.database,
      id: 'server:user:external',
      status: 'queued',
      jobId: 'job-id',
    );
    await harness.start();
    final item = harness.state.imports.single;

    await harness.controller.removeFromQueue(item);
    await settle();

    expect(harness.sent, contains('DELETE /api/queue/item'));
    expect(harness.state.imports, isEmpty);
    expect(
      await harness.database.getDowntifyImports('server', 'user'),
      isEmpty,
    );
  });

  group('saved-progress recovery', () {
    test('restarts every nonterminal status through normal effects', () async {
      SharedPreferences.setMockInitialValues({'downtifyServerUrl': _origin});
      final harness = _Harness(queueResponses: [<Object>[]]);
      addTearDown(harness.dispose);
      for (final entry in {
        'sub': 'submitting',
        'ret': 'retrying',
        'que': 'queued',
        'dow': 'downloading',
        'req': 'requestingScan',
        'wai': 'waitingForJellyfin',
        'den': 'scanDenied',
      }.entries) {
        await _seedImport(
          harness.database,
          id: 'server:user:${entry.key}',
          status: entry.value,
          externalSongId: entry.key,
        );
      }
      await harness.start();
      await harness.scheduler.advance(const Duration(seconds: 1));
      await settle();

      final byId = {
        for (final item in harness.state.imports) item.externalSongId: item,
      };
      // Interrupted submissions become terminal failures for manual retry.
      expect(byId['sub']!.status, 'downloadFailed');
      expect(byId['ret']!.status, 'downloadFailed');
      // Queued work resumes polling without resubmission.
      expect(byId['que']!.status, 'queued');
      expect(byId['dow']!.status, 'downloading');
      // Saved scans schedule a batch without a remote job.
      // Catalog-only rows resume catalog checks.
      expect(byId['wai']!.status, 'waitingForJellyfin');
      expect(byId['den']!.status, 'scanDenied');
      expect(
        harness.sent.where((call) => call.contains('/api/download/batch')),
        isEmpty,
      );
      expect(byId['req']!.status, 'waitingForJellyfin');
      expect(harness.scanRequests, 1);
    });

    test('adopts confirmed jobs by differing job and song ids', () async {
      SharedPreferences.setMockInitialValues({'downtifyServerUrl': _origin});
      final harness = _Harness(
        queueResponses: [
          <Object>[],
          [_jobJson('song-9', 'downloading', progress: 55)],
        ],
      );
      addTearDown(harness.dispose);
      await _seedImport(
        harness.database,
        id: 'server:user:song-9',
        status: 'submitting',
        externalSongId: 'song-9',
        jobId: 'job-9',
      );
      await harness.start();
      await settle();

      final item = harness.state.imports.single;
      expect(item.status, 'downloading');
      expect(item.progress, 55);
    });

    test('failed queue reads keep waiting rows without timing out', () async {
      SharedPreferences.setMockInitialValues({'downtifyServerUrl': _origin});
      final harness = _Harness(queueResponses: [Exception('boom')], tracks: []);
      addTearDown(harness.dispose);
      await _seedImport(
        harness.database,
        id: 'server:user:w',
        status: 'waitingForJellyfin',
        externalSongId: 'w',
        createdAt: harness.scheduler.now(),
      );
      await harness.start();
      await harness.controller.poll();
      await settle();

      expect(harness.state.imports.single.status, 'waitingForJellyfin');
    });

    test('scan denial pauses while other failures wait for Jellyfin', () async {
      SharedPreferences.setMockInitialValues({'downtifyServerUrl': _origin});
      final denied = _Harness(
        queueResponses: [
          <Object>[],
          [_jobJson('a', 'done', filename: 'A.mp3')],
        ],
        scanStatus: 403,
      );
      addTearDown(denied.dispose);
      await _seedImport(
        denied.database,
        id: 'server:user:a',
        status: 'queued',
        externalSongId: 'a',
      );
      await denied.start();
      await denied.controller.poll();
      await denied.scheduler.advance(const Duration(seconds: 1));
      await settle();

      expect(denied.state.imports.single.status, 'scanDenied');
      expect(
        denied.state.notices.map((notice) => notice.message),
        contains(contains('scheduled scan')),
      );

      final failed = _Harness(
        queueResponses: [
          <Object>[],
          [_jobJson('b', 'done', filename: 'B.mp3')],
        ],
        scanStatus: 500,
      );
      addTearDown(failed.dispose);
      await _seedImport(
        failed.database,
        id: 'server:user:b',
        status: 'queued',
        externalSongId: 'b',
      );
      await failed.start();
      await failed.controller.poll();
      await failed.scheduler.advance(const Duration(seconds: 1));
      await settle();

      expect(failed.state.imports.single.status, 'waitingForJellyfin');
    });

    test(
      'a download completing during a scan gets a follow-up batch',
      () async {
        SharedPreferences.setMockInitialValues({'downtifyServerUrl': _origin});
        final harness = _Harness(
          queueResponses: [
            <Object>[],
            <Object>[],
            [_jobJson('b', 'done', filename: 'B.mp3')],
          ],
        );
        addTearDown(harness.dispose);
        await _seedImport(
          harness.database,
          id: 'server:user:a',
          status: 'requestingScan',
          externalSongId: 'a',
        );
        await _seedImport(
          harness.database,
          id: 'server:user:b',
          status: 'queued',
          externalSongId: 'b',
        );
        await harness.start();
        harness.scanGate = Completer<void>();
        await harness.scheduler.advance(const Duration(seconds: 1));
        await settle();
        // Scan batch captured only A; B completes while it is in flight.
        await harness.controller.poll();
        await settle();
        expect(
          harness.state.imports
              .singleWhere((item) => item.externalSongId == 'b')
              .status,
          'requestingScan',
        );
        harness.scanGate!.complete();
        await settle();
        await harness.scheduler.advance(const Duration(seconds: 1));
        await settle();

        expect(harness.scanRequests, 2);
        expect(harness.state.imports.map((item) => item.status).toSet(), {
          'waitingForJellyfin',
        });
      },
    );

    test('terminal states never regress on later queue events', () async {
      SharedPreferences.setMockInitialValues({'downtifyServerUrl': _origin});
      final harness = _Harness(
        queueResponses: [
          [
            _jobJson('i', 'error', message: 'late'),
            _jobJson('f', 'downloading', progress: 10),
            _jobJson('t', 'done', filename: 'T.mp3'),
          ],
        ],
      );
      addTearDown(harness.dispose);
      await _seedImport(
        harness.database,
        id: 'server:user:i',
        status: 'imported',
        externalSongId: 'i',
      );
      await _seedImport(
        harness.database,
        id: 'server:user:f',
        status: 'downloadFailed',
        externalSongId: 'f',
      );
      await _seedImport(
        harness.database,
        id: 'server:user:t',
        status: 'importTimedOut',
        externalSongId: 't',
      );
      await harness.start();
      await harness.controller.poll();
      await settle();

      final byId = {
        for (final item in harness.state.imports) item.externalSongId: item,
      };
      expect(byId['i']!.status, 'imported');
      expect(byId['f']!.status, 'downloadFailed');
      expect(byId['t']!.status, 'importTimedOut');
    });

    test('restart at retry exhaustion emits one notice', () async {
      SharedPreferences.setMockInitialValues({'downtifyServerUrl': _origin});
      final fresh = _Harness(
        queueResponses: [
          [_jobJson('e', 'error', message: 'No match')],
        ],
      );
      addTearDown(fresh.dispose);
      await _seedImport(
        fresh.database,
        id: 'server:user:e',
        status: 'retrying',
        externalSongId: 'e',
        retryCount: 3,
      );
      await fresh.start();
      await fresh.controller.poll();
      await settle();

      expect(fresh.state.imports.single.status, 'downloadFailed');
      expect(fresh.state.notices, hasLength(1));

      final silent = _Harness(
        queueResponses: [
          [_jobJson('e', 'error', message: 'No match')],
        ],
      );
      addTearDown(silent.dispose);
      await _seedImport(
        silent.database,
        id: 'server:user:e',
        status: 'retrying',
        externalSongId: 'e',
        retryCount: 3,
        messageShown: true,
      );
      await silent.start();
      await silent.controller.poll();
      await settle();

      expect(silent.state.imports.single.status, 'downloadFailed');
      expect(silent.state.notices, isEmpty);
    });

    test('timeout needs more than fifteen minutes after a check', () async {
      SharedPreferences.setMockInitialValues({'downtifyServerUrl': _origin});
      final harness = _Harness(queueResponses: [<Object>[]], tracks: []);
      addTearDown(harness.dispose);
      final now = harness.scheduler.now();
      await _seedImport(
        harness.database,
        id: 'server:user:exact',
        status: 'waitingForJellyfin',
        externalSongId: 'exact',
        createdAt: now.subtract(const Duration(minutes: 15)),
      );
      await _seedImport(
        harness.database,
        id: 'server:user:old',
        status: 'waitingForJellyfin',
        externalSongId: 'old',
        createdAt: now.subtract(const Duration(minutes: 15, seconds: 1)),
      );
      await harness.start();
      await harness.controller.poll();
      await settle();

      final byId = {
        for (final item in harness.state.imports) item.externalSongId: item,
      };
      expect(byId['exact']!.status, 'waitingForJellyfin');
      expect(byId['old']!.status, 'importTimedOut');
    });

    test('failed catalog refresh never times an import out', () async {
      SharedPreferences.setMockInitialValues({'downtifyServerUrl': _origin});
      final harness = _Harness(queueResponses: [<Object>[]], tracksStatus: 500);
      addTearDown(harness.dispose);
      await _seedImport(
        harness.database,
        id: 'server:user:old',
        status: 'waitingForJellyfin',
        externalSongId: 'old',
        createdAt: harness.scheduler.now().subtract(const Duration(hours: 1)),
      );
      await harness.start();
      await harness.controller.poll();
      await settle();

      expect(harness.state.imports.single.status, 'waitingForJellyfin');
    });
  });

  group('account, origin, and attempt guards', () {
    test('late account restoration loads current work', () async {
      SharedPreferences.setMockInitialValues({'downtifyServerUrl': _origin});
      final harness = _Harness(queueResponses: [<Object>[]]);
      addTearDown(harness.dispose);
      await _seedImport(
        harness.database,
        id: 'server:user:late',
        status: 'queued',
        externalSongId: 'late',
      );
      final subscription = harness.container.listen(
        downtifyControllerProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await settle();
      expect(harness.state.imports, isEmpty);

      harness.container.read(accountScopeProvider).activate(_session);
      await settle();

      expect(harness.state.imports.map((item) => item.externalSongId), [
        'late',
      ]);
    });

    test('account switch clears the view and keeps stored rows', () async {
      SharedPreferences.setMockInitialValues({'downtifyServerUrl': _origin});
      final harness = _Harness(queueResponses: [<Object>[]]);
      addTearDown(harness.dispose);
      await _seedImport(
        harness.database,
        id: 'server:user:a',
        status: 'queued',
        externalSongId: 'a',
      );
      await harness.start();
      expect(harness.state.imports, hasLength(1));

      harness.container
          .read(accountScopeProvider)
          .activate(
            const JellyfinSession(
              serverUrl: 'https://jellyfin.example.com',
              serverId: 'server',
              deviceId: 'device',
              userId: 'other',
              userName: 'Other',
              accessToken: 'token',
            ),
          );
      await settle();
      expect(harness.state.imports, isEmpty);
      expect(
        await harness.database.getDowntifyImports('server', 'user'),
        hasLength(1),
      );
    });

    test('configuration removal keeps rows but resets the view', () async {
      SharedPreferences.setMockInitialValues({'downtifyServerUrl': _origin});
      final harness = _Harness(queueResponses: [<Object>[]]);
      addTearDown(harness.dispose);
      await _seedImport(
        harness.database,
        id: 'server:user:a',
        status: 'queued',
        externalSongId: 'a',
      );
      await harness.start();
      expect(harness.state.imports, hasLength(1));

      await harness.controller.removeConfiguration();
      await settle();

      expect(harness.state.availability, DowntifyAvailability.unconfigured);
      expect(harness.state.imports, isEmpty);
      expect(
        await harness.database.getDowntifyImports('server', 'user'),
        hasLength(1),
      );
    });

    test('disposal during held responses drops their effects', () async {
      SharedPreferences.setMockInitialValues({'downtifyServerUrl': _origin});
      final harness = _Harness(queueResponses: [<Object>[]]);
      harness.queueGate = Completer<void>();
      final subscription = harness.container.listen(
        downtifyControllerProvider,
        (_, _) {},
        fireImmediately: true,
      );
      harness.container.read(accountScopeProvider).activate(_session);
      await settle();
      final polling = harness.controller.poll();
      await settle();
      subscription.close();
      harness.container.dispose();
      harness.queueGate!.complete();
      await polling;
      await settle();
      harness.downtifyClient.close();
      harness.jellyfinClient.close();
      await harness.database.close();
    });

    test('latest configuration wins over late completions', () async {
      SharedPreferences.setMockInitialValues({});
      final harness = _Harness(queueResponses: [<Object>[]]);
      addTearDown(harness.dispose);
      final subscription = harness.container.listen(
        downtifyControllerProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await settle();

      harness.versionGate = Completer<void>();
      final gate = harness.versionGate!;
      final configuring = harness.controller.configure(_origin);
      await settle();
      await harness.controller.configure('https://other.example.com');
      await settle();
      gate.complete();
      await configuring;
      await settle();

      expect(harness.state.serverUrl, 'https://other.example.com');
      expect(harness.state.availability, DowntifyAvailability.available);
    });

    test('url switch during a poll keeps the new origin rows', () async {
      SharedPreferences.setMockInitialValues({'downtifyServerUrl': _origin});
      final harness = _Harness(queueResponses: [<Object>[]]);
      addTearDown(harness.dispose);
      await _seedImport(
        harness.database,
        id: 'server:user:a',
        status: 'queued',
        externalSongId: 'a',
      );
      await harness.start();
      harness.queueGate = Completer<void>();
      final polling = harness.controller.poll();
      await settle();
      // Switch origin mid-poll: the old response must not touch the new
      // origin's rows.
      await harness.controller.configure('https://other.example.com');
      harness.queueGate!.complete();
      await polling;
      await settle();

      expect(harness.state.serverUrl, 'https://other.example.com');
      // The old row stays stored and visible but no work ran on it: the
      // stale poll returned before touching anything.
      expect(harness.state.imports.map((item) => item.externalSongId), ['a']);
      expect(harness.state.imports.single.status, 'queued');
      expect(
        harness.sent.where((call) => call.contains('/api/download/batch')),
        isEmpty,
      );
    });

    test('retry during a poll defeats the stale response', () async {
      SharedPreferences.setMockInitialValues({'downtifyServerUrl': _origin});
      final harness = _Harness(
        queueResponses: [
          [_jobJson('r', 'downloading', progress: 10)],
        ],
      );
      addTearDown(harness.dispose);
      await _seedImport(
        harness.database,
        id: 'server:user:r',
        status: 'downloadFailed',
        externalSongId: 'r',
      );
      await harness.start();
      harness.queueGate = Completer<void>();
      final polling = harness.controller.poll();
      await settle();
      final item = harness.state.imports.single;
      await harness.controller.retry(item);
      harness.queueGate!.complete();
      await polling;
      await settle();

      // The stale poll cannot alter the fresh retry attempt.
      final fresh = harness.state.imports.single;
      expect(fresh.downtifyUrl, _origin);
      expect(fresh.status, isNot('downloading'));
    });

    test('dismiss during a poll cannot recreate the row', () async {
      SharedPreferences.setMockInitialValues({'downtifyServerUrl': _origin});
      final harness = _Harness(
        queueResponses: [
          [_jobJson('d', 'downloading', progress: 10)],
        ],
      );
      addTearDown(harness.dispose);
      await _seedImport(
        harness.database,
        id: 'server:user:d',
        status: 'queued',
        externalSongId: 'd',
      );
      await harness.start();
      harness.queueGate = Completer<void>();
      final polling = harness.controller.poll();
      await settle();
      await harness.controller.dismiss(harness.state.imports.single);
      harness.queueGate!.complete();
      await polling;
      await settle();

      expect(harness.state.imports, isEmpty);
      expect(
        await harness.database.getDowntifyImports('server', 'user'),
        isEmpty,
      );
    });

    test('removed false still removes the local row', () async {
      SharedPreferences.setMockInitialValues({'downtifyServerUrl': _origin});
      final harness = _Harness(queueResponses: [], deleteRemoved: false);
      addTearDown(harness.dispose);
      await _seedImport(
        harness.database,
        id: 'server:user:r',
        status: 'queued',
        externalSongId: 'r',
        jobId: 'job-r',
      );
      await harness.start();

      await harness.controller.removeFromQueue(harness.state.imports.single);
      await settle();

      expect(harness.state.imports, isEmpty);
    });

    test('foreign origins stay paused until their url returns', () async {
      SharedPreferences.setMockInitialValues({'downtifyServerUrl': _origin});
      final harness = _Harness(
        queueResponses: [
          <Object>[],
          [_jobJson('mine', 'downloading', progress: 80)],
          <Object>[],
          [_jobJson('away', 'downloading', progress: 30)],
        ],
      );
      addTearDown(harness.dispose);
      await _seedImport(
        harness.database,
        id: 'server:user:mine',
        status: 'queued',
        externalSongId: 'mine',
      );
      await _seedImport(
        harness.database,
        id: 'server:user:away',
        status: 'queued',
        externalSongId: 'away',
        origin: 'https://other.example.com',
      );
      await harness.start();
      await harness.controller.poll();
      await settle();

      final byId = {
        for (final item in harness.state.imports) item.externalSongId: item,
      };
      // Current origin adopted progress; the other origin never ran.
      expect(byId['mine']!.status, 'downloading');
      expect(byId['mine']!.progress, 80);
      expect(byId['away']!.status, 'queued');
      expect(harness.sent.where((call) => call.contains('away')), isEmpty);

      // Selecting the original URL again resumes its saved work.
      await harness.controller.configure('https://other.example.com');
      await settle();
      await harness.controller.poll();
      await settle();
      await harness.controller.poll();
      await settle();
      expect(
        harness.state.imports
            .singleWhere((item) => item.externalSongId == 'away')
            .status,
        'downloading',
      );
    });

    test('manual retry moves a terminal row to the current origin', () async {
      SharedPreferences.setMockInitialValues({'downtifyServerUrl': _origin});
      final harness = _Harness(queueResponses: [<Object>[]]);
      addTearDown(harness.dispose);
      await _seedImport(
        harness.database,
        id: 'server:user:old',
        status: 'downloadFailed',
        externalSongId: 'old',
        origin: 'https://other.example.com',
      );
      await harness.start();

      await harness.controller.retry(harness.state.imports.single);
      await settle();

      final fresh = harness.state.imports.single;
      expect(fresh.downtifyUrl, _origin);
      expect(fresh.retryCount, 0);
      expect(
        await harness.database.getDowntifyImports('server', 'user'),
        hasLength(1),
      );
    });

    test('same song across origins cannot enqueue twice', () async {
      SharedPreferences.setMockInitialValues({'downtifyServerUrl': _origin});
      final harness = _Harness(queueResponses: [<Object>[]]);
      addTearDown(harness.dispose);
      await _seedImport(
        harness.database,
        id: 'server:user:dup',
        status: 'queued',
        externalSongId: 'dup',
        origin: 'https://other.example.com',
      );
      await harness.start();

      expect(harness.controller.importFor('dup'), isNotNull);
      await harness.controller.enqueue(_song('dup', 'Dup'));
      await settle();

      expect(
        await harness.database.getDowntifyImports('server', 'user'),
        hasLength(1),
      );
    });

    test('stale search results never publish', () async {
      SharedPreferences.setMockInitialValues({'downtifyServerUrl': _origin});
      final searches = <String>[];
      final searchGate = Completer<void>();
      final harness = _Harness(
        queueResponses: [<Object>[]],
        onDowntifyRequest: (request) async {
          if (request.url.path == '/api/songs/search') {
            final query = request.url.queryParameters['query'] ?? '';
            searches.add(query);
            if (query == 'aborted-query') await searchGate.future;
            return http.Response(
              jsonEncode([
                {
                  'song_id': 'found-$query',
                  'name': 'Found',
                  'artists': ['Artist'],
                },
              ]),
              200,
            );
          }
          return null;
        },
      );
      addTearDown(harness.dispose);
      await harness.start();
      harness.controller.search('aborted-query');
      await harness.scheduler.advance(const Duration(milliseconds: 300));
      harness.controller.search('kept-query');
      await harness.scheduler.advance(const Duration(milliseconds: 300));
      await settle();
      searchGate.complete();
      await settle();

      expect(harness.state.results.map((song) => song.id), [
        'found-kept-query',
      ]);
      expect(searches, contains('kept-query'));
    });
  });
}

class _AuthenticatedAppController extends AppController {
  @override
  AppState build() => const AppState(
    status: AppStatus.ready,
    session: JellyfinSession(
      serverUrl: 'https://jellyfin.example.com',
      serverId: 'server',
      deviceId: 'device',
      userId: 'user',
      userName: 'Pablo',
      accessToken: 'token',
    ),
  );

  @override
  Future<void> refresh({bool silent = false, bool force = false}) async {}
}
