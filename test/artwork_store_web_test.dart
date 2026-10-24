@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart' show ImageProvider;
import 'package:spotifin/platform/artwork_store_web.dart';
import 'package:web/web.dart' as web;

@JS('Promise.resolve')
external JSPromise<web.Response> _resolvePromise(web.Response response);

const _cacheName = 'spotifin-artwork-v1';
const _accountId = 'test-account';
const _imageWidth = 64;
var _itemId = 0;

void main() {
  late _FetchHarness fetch;
  late web.Cache cache;
  final testKeys = <String>{};

  setUp(() async {
    cache = await web.window.caches.open(_cacheName).toDart;
    fetch = _FetchHarness()..install();
  });

  tearDown(() async {
    fetch.restore();
    for (final key in testKeys) {
      await cache.delete(key.toJS).toDart;
    }
    testKeys.clear();
  });

  test('stalled bodies release concurrent waiters and allow a retry', () async {
    final itemId = _nextItemId();
    final key = _key(itemId);
    testKeys.add(key);
    final store = ArtworkStore(timeout: const Duration(milliseconds: 100));
    late _ControlledBody stalledBody;
    fetch.respond((_, init) {
      stalledBody = fetch.stalledBody(init, abortWithError: true);
      return web.Response(stalledBody.stream, web.ResponseInit(status: 200));
    });

    final first = _resolve(store, itemId);
    final second = _resolve(store, itemId);
    try {
      await fetch.waitForCalls(1).timeout(const Duration(seconds: 1));
      await stalledBody.started.future;
      final results = await Future.wait([first, second])
          .timeout(const Duration(seconds: 2));

      expect(results, everyElement(isNull));
      expect(fetch.calls, 1);
      expect(fetch.aborts, 1);
      expect(await cache.match(key.toJS).toDart, isNull);

      fetch.respond((_, _) => web.Response('healthy artwork'.toJS));
      expect(await _resolve(store, itemId), isNotNull);
      expect(fetch.calls, 2);
    } finally {
      store.dispose();
    }
  });

  test('reads an existing cached response without fetching', () async {
    final itemId = _nextItemId();
    final key = _key(itemId);
    testKeys.add(key);
    await cache.put(key.toJS, web.Response('cached artwork'.toJS)).toDart;
    final store = ArtworkStore(timeout: const Duration(seconds: 1));

    try {
      expect(await _resolve(store, itemId), isNotNull);
      expect(fetch.calls, 0);
    } finally {
      store.dispose();
    }
  });

  test('caches a fresh successful response', () async {
    final itemId = _nextItemId();
    final key = _key(itemId);
    testKeys.add(key);
    final store = ArtworkStore(timeout: const Duration(seconds: 1));
    fetch.respond((_, _) => web.Response('fresh artwork'.toJS));

    try {
      expect(await _resolve(store, itemId), isNotNull);
      expect(fetch.calls, 1);
      expect(await cache.match(key.toJS).toDart, isNotNull);
    } finally {
      store.dispose();
    }
  });

  test('returns null for a non-success response', () async {
    final itemId = _nextItemId();
    final key = _key(itemId);
    testKeys.add(key);
    final store = ArtworkStore(timeout: const Duration(seconds: 1));
    fetch.respond(
      (_, _) => web.Response('not found'.toJS, web.ResponseInit(status: 404)),
    );

    try {
      expect(await _resolve(store, itemId), isNull);
      expect(fetch.calls, 1);
      expect(await cache.match(key.toJS).toDart, isNull);
    } finally {
      store.dispose();
    }
  });

  test('returns null when reading a response body fails', () async {
    final itemId = _nextItemId();
    final key = _key(itemId);
    testKeys.add(key);
    final store = ArtworkStore(timeout: const Duration(seconds: 1));
    fetch.respond((_, _) {
      final source = JSObject();
      source['start'] = ((web.ReadableStreamDefaultController controller) {
        controller.error();
      }).toJS;
      return web.Response(web.ReadableStream(source));
    });

    try {
      expect(await _resolve(store, itemId), isNull);
      expect(fetch.calls, 1);
      expect(await cache.match(key.toJS).toDart, isNull);
    } finally {
      store.dispose();
    }
  });

  test('dispose aborts pending fetch and body reads', () async {
    final itemId = _nextItemId();
    testKeys.add(_key(itemId));
    final store = ArtworkStore(timeout: const Duration(seconds: 2));
    late _ControlledBody stalledBody;
    fetch.respond((_, init) {
      stalledBody = fetch.stalledBody(init, abortWithError: true);
      return web.Response(stalledBody.stream, web.ResponseInit(status: 200));
    });
    final pending = _resolve(store, itemId);

    await fetch.waitForCalls(1).timeout(const Duration(seconds: 1));
    await stalledBody.started.future;
    store.dispose();

    expect(await pending.timeout(const Duration(seconds: 1)), isNull);
    expect(fetch.aborts, 1);
  });

  test(
    'a late timed-out operation cannot clear a newer pending retry',
    () async {
      final itemId = _nextItemId();
      final key = _key(itemId);
      testKeys.add(key);
      final store = ArtworkStore(timeout: const Duration(milliseconds: 500));
      final cachePut = _CachePutGate(cache)..install();
      fetch.respond((_, _) => web.Response('first artwork'.toJS));

      try {
        final first = _resolve(store, itemId);
        await fetch
            .waitForCalls(1)
            .timeout(
              const Duration(seconds: 1),
              onTimeout: () {
                throw TimeoutException('first fetch did not start');
              },
            );
        await cachePut
            .waitForCalls(1)
            .timeout(
              const Duration(seconds: 1),
              onTimeout: () {
                throw TimeoutException('first cache write did not start');
              },
            );
        expect(
          await first.timeout(
            const Duration(seconds: 1),
            onTimeout: () {
              throw TimeoutException('first resolution did not time out');
            },
          ),
          isNull,
        );

        fetch.respond((_, _) => web.Response('retry artwork'.toJS));
        final retry = _resolve(store, itemId);
        await fetch
            .waitForCalls(2)
            .timeout(
              const Duration(seconds: 1),
              onTimeout: () {
                throw TimeoutException('retry fetch did not start');
              },
            );
        await cachePut
            .waitForCalls(2)
            .timeout(
              const Duration(seconds: 1),
              onTimeout: () {
                throw TimeoutException('retry cache write did not start');
              },
            );

        final concurrentRetry = _resolve(store, itemId);
        expect(identical(concurrentRetry, retry), isTrue);

        cachePut.completeFirst();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(identical(_resolve(store, itemId), retry), isTrue);
        expect(fetch.calls, 2);

        await cachePut.completeSecond();
        final results = await Future.wait([retry, concurrentRetry])
            .timeout(const Duration(seconds: 1));
        expect(results, everyElement(isNotNull));
        expect(await _cacheText(cache, key), 'retry artwork');
      } finally {
        cachePut.completeFirst();
        await cachePut.completeSecond();
        cachePut.restore();
        store.dispose();
      }
    },
  );
}

String _nextItemId() => 'artwork-test-${_itemId++}';

String _key(String itemId) =>
    '/.spotifin/artwork/$_accountId/${Uri.encodeComponent(itemId)}/$_imageWidth';

Future<ImageProvider?> _resolve(ArtworkStore store, String itemId) =>
    store.resolve(
      _accountId,
      itemId,
      _imageWidth,
      Uri.https('example.test', '/artwork'),
    );

typedef _ResponseFactory = web.Response Function(JSAny? input, JSAny? init);

class _FetchHarness {
  final _responses = <_ResponseFactory>[];
  final _callCounts = StreamController<int>.broadcast(sync: true);
  late JSFunction _originalFetch;
  bool _installed = false;
  int calls = 0;
  int aborts = 0;

  void install() {
    _originalFetch = globalContext['fetch'] as JSFunction;
    globalContext['fetch'] = ((JSAny? input, JSAny? init) {
      calls++;
      final response = _responses.removeAt(0)(input, init);
      _callCounts.add(calls);
      return _resolvePromise(response);
    }).toJS;
    _installed = true;
  }

  void respond(_ResponseFactory response) => _responses.add(response);

  Future<void> waitForCalls(int target) async {
    if (calls >= target) return;
    await _callCounts.stream.firstWhere((count) => count >= target);
  }

  _ControlledBody stalledBody(JSAny? init, {required bool abortWithError}) {
    final body = _ControlledBody(
      onAbort: () => aborts++,
      abortWithError: abortWithError,
    );
    (init as web.RequestInit).signal!.addEventListener(
      'abort',
      ((JSAny? _) => body.abort()).toJS,
    );
    return body;
  }

  void restore() {
    if (_installed) globalContext['fetch'] = _originalFetch;
    unawaited(_callCounts.close());
  }
}

class _ControlledBody {
  _ControlledBody({required this.onAbort, required this.abortWithError}) {
    final source = JSObject();
    source['start'] = ((web.ReadableStreamDefaultController controller) {
      _controller = controller;
      if (!started.isCompleted) started.complete();
      if (_abortRequested && abortWithError) controller.error();
    }).toJS;
    stream = web.ReadableStream(source);
  }

  final void Function() onAbort;
  final bool abortWithError;
  final started = Completer<void>();
  late final web.ReadableStream stream;
  web.ReadableStreamDefaultController? _controller;
  bool _abortRequested = false;

  void abort() {
    _abortRequested = true;
    onAbort();
    if (abortWithError) _controller?.error();
  }

  Future<void> writeAndClose(String text) async {
    await started.future;
    final controller = _controller!;
    controller.enqueue(web.TextEncoder().encode(text));
    controller.close();
  }
}

class _CachePutGate {
  _CachePutGate(this.cache);

  final web.Cache cache;
  late JSObject _cachePrototype;
  final firstPut = Completer<JSAny?>();
  final secondPut = Completer<JSAny?>();
  final firstCall = Completer<void>();
  final secondCall = Completer<void>();
  late JSFunction _originalPut;
  JSAny? _secondRequest;
  JSAny? _secondResponse;
  int calls = 0;

  void install() {
    _cachePrototype = JSObject.getPrototypeOf(cache)!;
    _originalPut = _cachePrototype['put'] as JSFunction;
    _cachePrototype['put'] =
        ((JSAny? receiver, JSAny? request, JSAny? response) {
          calls++;
          if (calls == 1) {
            firstCall.complete();
            return firstPut.future.toJS;
          }
          if (calls == 2) {
            _secondRequest = request;
            _secondResponse = response;
            secondCall.complete();
            return secondPut.future.toJS;
          }
          return _callOriginal(receiver, request, response);
        }).toJSCaptureThis;
  }

  Future<void> waitForCalls(int target) async {
    if (calls >= target) return;
    if (target == 1) await firstCall.future;
    if (target == 2) await secondCall.future;
  }

  void completeFirst() {
    if (!firstPut.isCompleted) firstPut.complete(null);
  }

  Future<void> completeSecond() async {
    if (_secondRequest == null || _secondResponse == null) return;
    if (secondPut.isCompleted) return;
    await (_originalPut.callAsFunction(
      cache,
      _secondRequest,
      _secondResponse,
    ) as JSPromise<JSAny?>).toDart;
    secondPut.complete(null);
  }

  JSPromise<JSAny?> _callOriginal(
    JSAny? receiver,
    JSAny? request,
    JSAny? response,
  ) =>
      _originalPut.callAsFunction(receiver, request, response)
          as JSPromise<JSAny?>;

  void restore() => _cachePrototype['put'] = _originalPut;
}

Future<String?> _cacheText(web.Cache cache, String key) async {
  final response = await cache.match(key.toJS).toDart;
  if (response == null) return null;
  return (await response.text().toDart).toDart;
}
