import 'dart:js_interop';

import 'package:web/web.dart' as web;

class DownloadStore {
  static const _cacheName = 'spotifin-audio-v1';

  Future<String> save(
    String accountId,
    String trackId,
    Uri source,
    Map<String, String> requestHeaders,
  ) async {
    final headers = web.Headers();
    requestHeaders.forEach((name, value) => headers.append(name, value));
    final response = await web.window
        .fetch(source.toString().toJS, web.RequestInit(headers: headers))
        .toDart;
    if (!response.ok) throw Exception('Download failed (${response.status}).');
    final key = '/.spotifin/audio/$accountId/$trackId';
    final cache = await web.window.caches.open(_cacheName).toDart;
    await cache.put(key.toJS, response).toDart;
    return key;
  }

  Future<Uri?> resolve(String storedUri) async {
    final cache = await web.window.caches.open(_cacheName).toDart;
    final response = await cache.match(storedUri.toJS).toDart;
    if (response == null) return null;
    final blob = await response.blob().toDart;
    return Uri.parse(web.URL.createObjectURL(blob));
  }

  Future<void> remove(String storedUri) async {
    final cache = await web.window.caches.open(_cacheName).toDart;
    await cache.delete(storedUri.toJS).toDart;
  }
}
