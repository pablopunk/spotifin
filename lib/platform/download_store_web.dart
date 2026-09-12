import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'download_store_exception.dart';

class DownloadStore {
  static const _cacheName = 'spotifin-audio-v1';
  final Map<String, String> _objectUrls = {};

  Future<String> save(
    String accountId,
    String trackId,
    Uri source,
    Map<String, String> requestHeaders,
    String extension,
  ) async {
    final headers = web.Headers();
    requestHeaders.forEach((name, value) => headers.append(name, value));
    final controller = web.AbortController();
    final timeout = Timer(
      const Duration(seconds: 30),
      () => controller.abort(),
    );
    late final web.Response response;
    try {
      response = await web.window
          .fetch(
            source.toString().toJS,
            web.RequestInit(headers: headers, signal: controller.signal),
          )
          .toDart;
    } finally {
      timeout.cancel();
    }
    if (!response.ok) {
      throw DownloadStoreException(
        'Download failed (${response.status}).',
        statusCode: response.status,
      );
    }
    final key = '/.spotifin/audio/$accountId/$trackId';
    final cache = await web.window.caches.open(_cacheName).toDart;
    await cache.put(key.toJS, response).toDart;
    return key;
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

  void dispose() {
    for (final objectUrl in _objectUrls.values) {
      web.URL.revokeObjectURL(objectUrl);
    }
    _objectUrls.clear();
  }
}
