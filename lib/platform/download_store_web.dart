import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'download_store_exception.dart';
import 'safe_path_segment.dart';

class DownloadStore {
  static const _cacheName = 'spotifin-audio-v1';
  static const _defaultTimeout = Duration(minutes: 5);

  final Map<String, String> _objectUrls = {};
  final Map<(String, String), _WebTransfer> _active = {};
  var _disposed = false;

  Future<String> save(
    String accountId,
    String trackId,
    Uri source,
    Map<String, String> requestHeaders,
    String extension, {
    Duration timeout = _defaultTimeout,
  }) async {
    if (_disposed) {
      throw const DownloadStoreException('Download store is disposed.');
    }
    final key = (accountId, trackId);
    final previous = _active[key];
    if (previous != null) await previous.cancelAndWait();
    if (_disposed) {
      throw const DownloadStoreException('Download store is disposed.');
    }

    final transfer = _WebTransfer(key, web.AbortController());
    _active[key] = transfer;
    final operation = _save(
      transfer,
      source,
      requestHeaders,
      accountId,
      trackId,
    );
    transfer.completion = operation;
    try {
      return await operation.timeout(
        timeout,
        onTimeout: () async {
          await transfer.cancelAndWait();
          throw TimeoutException('Download exceeded $timeout.');
        },
      );
    } finally {
      if (identical(_active[key], transfer)) _active.remove(key);
    }
  }

  Future<String> _save(
    _WebTransfer transfer,
    Uri source,
    Map<String, String> requestHeaders,
    String accountId,
    String trackId,
  ) async {
    final storedKey =
        '/.spotifin/audio/${safePathSegment(accountId)}/${safePathSegment(trackId)}';
    try {
      final headers = web.Headers();
      requestHeaders.forEach((name, value) => headers.append(name, value));
      final response = await web.window
          .fetch(
            source.toString().toJS,
            web.RequestInit(
              headers: headers,
              signal: transfer.controller.signal,
            ),
          )
          .toDart;
      _throwIfCancelled(transfer);
      if (!response.ok) {
        throw DownloadStoreException(
          'Download failed (${response.status}).',
          statusCode: response.status,
        );
      }

      final cache = await web.window.caches.open(_cacheName).toDart;
      _throwIfCancelled(transfer);
      await cache.put(storedKey.toJS, response).toDart;
      _throwIfCancelled(transfer);
      return storedKey;
    } catch (_) {
      if (transfer.cancelled) {
        await _deleteCacheEntry(transfer, storedKey);
        _throwIfCancelled(transfer);
      }
      rethrow;
    }
  }

  static void _throwIfCancelled(_WebTransfer transfer) {
    if (transfer.cancelled) {
      throw const DownloadStoreException('Download cancelled.');
    }
  }

  Future<void> _deleteCacheEntry(
    _WebTransfer transfer,
    String storedKey,
  ) async {
    if (!identical(_active[transfer.key], transfer)) return;
    try {
      final cache = await web.window.caches.open(_cacheName).toDart;
      if (identical(_active[transfer.key], transfer)) {
        await cache.delete(storedKey.toJS).toDart;
      }
    } catch (_) {}
  }

  Future<Uri?> resolve(String storedUri) async {
    final existing = _objectUrls[storedUri];
    if (existing != null) return Uri.parse(existing);
    final cache = await web.window.caches.open(_cacheName).toDart;
    final response = await cache.match(storedUri.toJS).toDart;
    if (response == null) return null;
    final blob = await response.blob().toDart;
    final objectUrl = web.URL.createObjectURL(blob);
    _objectUrls[storedUri] = objectUrl;
    return Uri.parse(objectUrl);
  }

  Future<void> remove(String storedUri) async {
    final objectUrl = _objectUrls.remove(storedUri);
    if (objectUrl != null) web.URL.revokeObjectURL(objectUrl);
    final cache = await web.window.caches.open(_cacheName).toDart;
    await cache.delete(storedUri.toJS).toDart;
  }

  Future<void> cancel(String accountId, String trackId) async {
    final transfer = _active[(accountId, trackId)];
    if (transfer != null) await transfer.cancelAndWait();
  }

  Future<void> cancelAll() async {
    await Future.wait(
      _active.values.toList().map((transfer) async {
        await transfer.cancelAndWait();
      }),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final transfer in _active.values.toList()) {
      unawaited(transfer.cancelAndWait());
    }
    for (final objectUrl in _objectUrls.values) {
      web.URL.revokeObjectURL(objectUrl);
    }
    _objectUrls.clear();
  }
}

class _WebTransfer {
  _WebTransfer(this.key, this.controller);

  final (String, String) key;
  final web.AbortController controller;
  bool cancelled = false;
  Future<String>? completion;
  Future<void>? _cancelFuture;

  Future<void> cancelAndWait() async {
    await (_cancelFuture ??= _cancel());
    final current = completion;
    if (current != null) {
      try {
        await current;
      } catch (_) {}
    }
  }

  Future<void> _cancel() async {
    cancelled = true;
    controller.abort();
  }
}
