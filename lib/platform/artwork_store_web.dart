import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

class ArtworkStore {
  static const _cacheName = 'spotifin-artwork-v1';

  ArtworkStore({this.timeout = const Duration(seconds: 10)});

  final Duration timeout;
  final Map<String, String> _objectUrls = {};
  final Map<String, Future<ImageProvider?>> _pending = {};
  final Map<String, _ArtworkResolution> _resolutions = {};

  Future<ImageProvider?> resolve(
    String accountId,
    String itemId,
    int width,
    Uri source,
  ) {
    final key =
        '/.spotifin/artwork/${Uri.encodeComponent(accountId)}/'
        '${Uri.encodeComponent(itemId)}/$width';
    final existingUrl = _objectUrls[key];
    if (existingUrl != null) return Future.value(NetworkImage(existingUrl));

    final pending = _pending[key];
    if (pending != null) return pending;

    final resolution = _ArtworkResolution();
    resolution.timer = Timer(timeout, resolution.abort);
    _resolutions[key] = resolution;

    final future = _resolve(key, source, resolution).timeout(
      timeout,
      onTimeout: () {
        resolution.abort();
        return null;
      },
    );
    _pending[key] = future;
    future.then(
      (_) => _release(key, future, resolution),
      onError: (Object error, StackTrace stackTrace) {
        _release(key, future, resolution);
      },
    );
    return future;
  }

  Future<ImageProvider?> _resolve(
    String key,
    Uri source,
    _ArtworkResolution resolution,
  ) async {
    try {
      final cache = await web.window.caches.open(_cacheName).toDart;
      if (!resolution.active) return null;

      var response = await cache.match(key.toJS).toDart;
      if (!resolution.active) return null;
      var shouldCache = false;
      if (response == null) {
        response = await web.window
            .fetch(
              source.toString().toJS,
              web.RequestInit(signal: resolution.controller.signal),
            )
            .toDart;
        if (!resolution.active) return null;
        if (!response.ok) {
          resolution.abort();
          return null;
        }
        shouldCache = true;
      }

      final blob = await _readBlob(response, resolution);
      if (blob == null || !resolution.active) return null;
      if (shouldCache) {
        final cacheResponse = web.Response(
          response.status == 204 || response.status == 205 ? null : blob,
          web.ResponseInit(
            status: response.status,
            statusText: response.statusText,
            headers: response.headers,
          ),
        );
        await cache.put(key.toJS, cacheResponse).toDart;
        if (!resolution.active) return null;
      }

      final objectUrl = web.URL.createObjectURL(blob);
      if (!resolution.active) {
        web.URL.revokeObjectURL(objectUrl);
        return null;
      }
      _objectUrls[key] = objectUrl;
      return NetworkImage(objectUrl);
    } catch (_) {
      return null;
    }
  }

  Future<web.Blob?> _readBlob(
    web.Response response,
    _ArtworkResolution resolution,
  ) async {
    final body = response.body;
    if (body == null) return web.Blob();

    final reader = body.getReader() as web.ReadableStreamDefaultReader;
    resolution.reader = reader;
    final chunks = <JSAny>[];
    try {
      while (resolution.active) {
        final result = await reader.read().toDart;
        if (!resolution.active) return null;
        if (result.done) break;
        final chunk = result.value;
        if (chunk != null) chunks.add(chunk);
      }
      if (!resolution.active) return null;

      return web.Blob(
        chunks.toJS,
        web.BlobPropertyBag(type: response.headers.get('content-type') ?? ''),
      );
    } finally {
      if (identical(resolution.reader, reader)) resolution.reader = null;
      reader.releaseLock();
    }
  }

  void _release(
    String key,
    Future<ImageProvider?> future,
    _ArtworkResolution resolution,
  ) {
    if (identical(_pending[key], future)) _pending.remove(key);
    if (identical(_resolutions[key], resolution)) {
      _resolutions.remove(key);
    }
    resolution.finish();
  }

  void dispose() {
    for (final resolution in _resolutions.values) {
      resolution.abort();
    }
    _resolutions.clear();
    _pending.clear();
    for (final objectUrl in _objectUrls.values) {
      web.URL.revokeObjectURL(objectUrl);
    }
    _objectUrls.clear();
  }
}

class _ArtworkResolution {
  final controller = web.AbortController();
  Timer? timer;
  web.ReadableStreamDefaultReader? reader;
  bool active = true;

  void abort() {
    if (!active) return;
    active = false;
    timer?.cancel();
    controller.abort();
    final currentReader = reader;
    if (currentReader != null) {
      unawaited(
        currentReader.cancel().toDart.then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) {},
        ),
      );
    }
  }

  void finish() {
    active = false;
    timer?.cancel();
  }
}
