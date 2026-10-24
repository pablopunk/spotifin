import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:spotifin/platform/download_store.dart';

const _accountId = 'account';
const _trackId = 'track';
const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'cancelling a trickling response closes it and removes the partial',
    () async {
      final harness = await _DownloadHarness.create(trickleModes: [true]);
      addTearDown(harness.close);

      final saving = harness.store.save(
        _accountId,
        _trackId,
        Uri.parse('http://download.example/audio'),
        const {},
        'mp3',
        timeout: const Duration(seconds: 3),
      );
      final client = await harness.clientAt(0);
      await client.headersSent.future.timeout(const Duration(seconds: 1));

      final saveFailure = expectLater(
        saving.timeout(const Duration(milliseconds: 250)),
        throwsA(isA<DownloadStoreException>()),
      );
      await harness.store
          .cancel(_accountId, _trackId)
          .timeout(const Duration(seconds: 1));
      await saveFailure;
      await client.responseSettled.future.timeout(const Duration(seconds: 1));

      expect(client.closed, isTrue);
      expect(await harness.partialFiles(), isEmpty);
    },
  );

  test(
    'a stalled response times out, closes the connection and removes partial',
    () async {
      final harness = await _DownloadHarness.create(trickleModes: [false]);
      addTearDown(harness.close);

      final saving = harness.store.save(
        _accountId,
        _trackId,
        Uri.parse('http://download.example/audio'),
        const {},
        'mp3',
        timeout: const Duration(milliseconds: 150),
      );
      final client = await harness.clientAt(0);
      await client.headersSent.future.timeout(const Duration(seconds: 1));

      await expectLater(saving, throwsA(isA<TimeoutException>()));
      await client.responseSettled.future.timeout(const Duration(seconds: 1));

      expect(client.closed, isTrue);
      expect(await harness.partialFiles(), isEmpty);
    },
  );

  test('repeated cancellation cannot remove a replacement transfer', () async {
    final harness = await _DownloadHarness.create(
      trickleModes: [true, false],
      completionBodies: [
        null,
        [4, 5, 6],
      ],
    );
    addTearDown(harness.close);

    final firstSave = harness.store.save(
      _accountId,
      _trackId,
      Uri.parse('http://download.example/old'),
      const {},
      'mp3',
      timeout: const Duration(seconds: 3),
    );
    final firstClient = await harness.clientAt(0);
    await firstClient.headersSent.future.timeout(const Duration(seconds: 1));
    final firstFailure = expectLater(
      firstSave,
      throwsA(isA<DownloadStoreException>()),
    );

    final cancelFirst = harness.store.cancel(_accountId, _trackId);
    final replacementSave = harness.store.save(
      _accountId,
      _trackId,
      Uri.parse('http://download.example/new'),
      const {},
      'mp3',
      timeout: const Duration(seconds: 3),
    );
    final cancelAgain = harness.store.cancel(_accountId, _trackId);

    await Future.wait([cancelFirst, cancelAgain]);
    await firstFailure;
    final replacementUri = Uri.parse(await replacementSave);
    final replacementFile = File.fromUri(replacementUri);
    expect(await replacementFile.readAsBytes(), [4, 5, 6]);

    await harness.store.cancel(_accountId, _trackId);
    expect(await replacementFile.readAsBytes(), [4, 5, 6]);
    expect(await harness.partialFiles(), isEmpty);
  });

  test(
    'natural body completion racing cancellation leaves no partial file',
    () async {
      final harness = await _DownloadHarness.create(trickleModes: [false]);
      addTearDown(harness.close);

      final saving = harness.store.save(
        _accountId,
        _trackId,
        Uri.parse('http://download.example/audio'),
        const {},
        'mp3',
        timeout: const Duration(seconds: 3),
      );
      final client = await harness.clientAt(0);
      await client.headersSent.future.timeout(const Duration(seconds: 1));
      final result = saving.then<Object>(
        (uri) => uri,
        onError: (Object error) => error,
      );

      client.finishBody([7, 8, 9]);
      final cancelling = harness.store.cancel(_accountId, _trackId);
      final outcome = await result.timeout(const Duration(seconds: 1));
      await cancelling;

      expect(await harness.partialFiles(), isEmpty);
      if (outcome is String) {
        expect(await File.fromUri(Uri.parse(outcome)).readAsBytes(), [7, 8, 9]);
      } else {
        expect(outcome, isA<DownloadStoreException>());
      }
    },
  );

  test('disposing the store aborts active transfers', () async {
    final harness = await _DownloadHarness.create(trickleModes: [true]);
    addTearDown(harness.close);

    final saving = harness.store.save(
      _accountId,
      _trackId,
      Uri.parse('http://download.example/audio'),
      const {},
      'mp3',
      timeout: const Duration(seconds: 3),
    );
    final client = await harness.clientAt(0);
    await client.headersSent.future.timeout(const Duration(seconds: 1));
    final saveFailure = expectLater(
      saving,
      throwsA(isA<DownloadStoreException>()),
    );

    harness.store.dispose();
    await saveFailure;
    await client.responseSettled.future.timeout(const Duration(seconds: 1));

    expect(client.closed, isTrue);
    expect(await harness.partialFiles(), isEmpty);
  });
}

class _DownloadHarness {
  _DownloadHarness(this.root, this.store, this.clients, this.clientWaiters);

  final Directory root;
  final DownloadStore store;
  final List<_StreamingClient> clients;
  final List<Completer<_StreamingClient>> clientWaiters;

  static Future<_DownloadHarness> create({
    required List<bool> trickleModes,
    List<List<int>?> completionBodies = const [],
  }) async {
    final root = await Directory.systemTemp.createTemp('spotifin-download-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return root.path;
          }
          throw MissingPluginException('Unexpected path provider call.');
        });
    final clients = <_StreamingClient>[];
    final clientWaiters = <Completer<_StreamingClient>>[];
    final store = DownloadStore(
      clientFactory: () {
        final index = clients.length;
        final client = _StreamingClient(
          trickle: trickleModes[index.clamp(0, trickleModes.length - 1)],
          completionBody: index < completionBodies.length
              ? completionBodies[index]
              : null,
        );
        clients.add(client);
        if (index < clientWaiters.length && !clientWaiters[index].isCompleted) {
          clientWaiters[index].complete(client);
        }
        return client;
      },
    );
    return _DownloadHarness(root, store, clients, clientWaiters);
  }

  Future<_StreamingClient> clientAt(int index) {
    if (clients.length > index) return Future.value(clients[index]);
    while (clientWaiters.length <= index) {
      clientWaiters.add(Completer<_StreamingClient>());
    }
    return clientWaiters[index].future;
  }

  Future<List<FileSystemEntity>> partialFiles() async {
    final directory = Directory('${root.path}/downloads/$_accountId');
    if (!await directory.exists()) return const [];
    return directory
        .list()
        .where((entry) => entry.path.endsWith('.partial'))
        .toList();
  }

  Future<void> close() async {
    await store.cancelAll();
    store.dispose();
    for (final client in clients) {
      client.close();
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    if (await root.exists()) await root.delete(recursive: true);
  }
}

class _StreamingClient extends http.BaseClient {
  _StreamingClient({required this.trickle, this.completionBody}) {
    _body = StreamController<List<int>>(
      onListen: () {
        if (trickle) {
          _ticker = Timer.periodic(
            const Duration(milliseconds: 10),
            (_) => _body.add(List<int>.filled(1024, 1)),
          );
        } else if (completionBody != null) {
          scheduleMicrotask(() => finishBody(completionBody!));
        }
      },
      onCancel: _markResponseSettled,
    );
  }

  final bool trickle;
  final List<int>? completionBody;
  final headersSent = Completer<void>();
  final responseSettled = Completer<void>();
  late final StreamController<List<int>> _body;
  Timer? _ticker;
  var closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!headersSent.isCompleted) headersSent.complete();
    return http.StreamedResponse(
      _body.stream.transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (chunk, sink) => sink.add(chunk),
          handleError: (error, stackTrace, sink) =>
              sink.addError(error, stackTrace),
          handleDone: (sink) {
            _markResponseSettled();
            sink.close();
          },
        ),
      ),
      HttpStatus.ok,
    );
  }

  void finishBody(List<int> bytes) {
    if (_body.isClosed) return;
    _ticker?.cancel();
    _body
      ..add(bytes)
      ..close();
  }

  @override
  void close() {
    if (closed) return;
    closed = true;
    _ticker?.cancel();
    if (!_body.isClosed) unawaited(_body.close());
    _markResponseSettled();
  }

  void _markResponseSettled() {
    _ticker?.cancel();
    if (!responseSettled.isCompleted) responseSettled.complete();
  }
}
