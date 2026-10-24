import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

class ArtworkStore {
  static const _cacheName = 'spotifin-artwork-v1';
  static const _revisionParameter = '__spotifin_artwork_revision';
  static int _revisionClock = DateTime.now().microsecondsSinceEpoch;

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

    final revision = _nextRevision();
    final resolution = _ArtworkResolution();
    resolution.timer = Timer(timeout, resolution.abort);
    _resolutions[key] = resolution;

    final future = _resolve(key, source, resolution, revision).timeout(
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
    int revision,
  ) async {
    try {
      final cache = await web.window.caches.open(_cacheName).toDart;
      if (!resolution.active) return null;

      final cached = await _latestCacheEntry(cache, key);
      if (!resolution.active) return null;
      var response = cached == null
          ? null
          : await cache.match(cached.key.toJS).toDart;
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
        final cacheKey = _versionedCacheKey(key, revision);
        try {
          await cache.put(cacheKey.toJS, cacheResponse).toDart;
        } catch (_) {
          await _deleteCacheEntry(cache, cacheKey);
          rethrow;
        }
        _pruneOlderCacheEntries(cache, key);
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

  static int _nextRevision() {
    final now = DateTime.now().microsecondsSinceEpoch;
    if (now > _revisionClock) {
      _revisionClock = now;
    } else {
      _revisionClock++;
    }
    return _revisionClock;
  }

  // Cache.put cannot be canceled, so late writes get an older, separate key.
  static String _versionedCacheKey(String key, int revision) =>
      '$key?$_revisionParameter=$revision';

  static Future<_ArtworkCacheEntry?> _latestCacheEntry(
    web.Cache cache,
    String key,
  ) async {
    final entries = await _cacheEntries(cache, key);
    if (entries.isEmpty) return null;
    var latest = entries.first;
    for (final entry in entries.skip(1)) {
      if (entry.revision > latest.revision) latest = entry;
    }
    return latest;
  }

  static Future<List<_ArtworkCacheEntry>> _cacheEntries(
    web.Cache cache,
    String key,
  ) async {
    final requests =
        (await cache
                .keys(key.toJS, web.CacheQueryOptions(ignoreSearch: true))
                .toDart)
            .toDart;
    final entries = <_ArtworkCacheEntry>[];
    for (final request in requests) {
      final revision = _cacheRevision(request.url, key);
      if (revision != null) {
        entries.add(_ArtworkCacheEntry(request.url, revision));
      }
    }
    return entries;
  }

  static int? _cacheRevision(String requestUrl, String key) {
    final keyStart = requestUrl.lastIndexOf(key);
    if (keyStart < 0) return null;
    final suffix = requestUrl.substring(keyStart + key.length);
    if (suffix.isEmpty) return 0;
    if (!suffix.startsWith('?')) return null;
    try {
      final query = Uri.splitQueryString(suffix.substring(1));
      return int.tryParse(query[_revisionParameter] ?? '');
    } on FormatException {
      return null;
    }
  }

  static Future<void> _deleteCacheEntry(web.Cache cache, String key) async {
    try {
      await cache.delete(key.toJS).toDart;
    } catch (_) {
      // A failed Cache.put must not mask the original resolution failure.
    }
  }

  static void _pruneOlderCacheEntries(web.Cache cache, String key) {
    unawaited(() async {
      try {
        final entries = await _cacheEntries(cache, key);
        if (entries.isEmpty) return;
        var newestRevision = entries.first.revision;
        for (final entry in entries.skip(1)) {
          if (entry.revision > newestRevision) {
            newestRevision = entry.revision;
          }
        }
        for (final entry in entries) {
          if (entry.revision < newestRevision) {
            await cache.delete(entry.key.toJS).toDart;
          }
        }
      } catch (_) {
        // Cache cleanup is best effort and must not extend the resolution.
      }
    }());
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

class _ArtworkCacheEntry {
  const _ArtworkCacheEntry(this.key, this.revision);

  final String key;
  final int revision;
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
