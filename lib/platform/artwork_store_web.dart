import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

class ArtworkStore {
  static const _cacheName = 'spotifin-artwork-v1';
  final Map<String, String> _objectUrls = {};
  final Map<String, Future<ImageProvider?>> _pending = {};

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
    return _pending.putIfAbsent(key, () {
      final future = _resolve(key, source);
      future.whenComplete(() => _pending.remove(key));
      return future;
    });
  }

  Future<ImageProvider?> _resolve(String key, Uri source) async {
    try {
      final cache = await web.window.caches.open(_cacheName).toDart;
      var response = await cache.match(key.toJS).toDart;
      if (response == null) {
        final controller = web.AbortController();
        final timeout = Timer(
          const Duration(seconds: 10),
          () => controller.abort(),
        );
        try {
          response = await web.window
              .fetch(
                source.toString().toJS,
                web.RequestInit(signal: controller.signal),
              )
              .toDart;
        } finally {
          timeout.cancel();
        }
        if (!response.ok) return null;
        await cache.put(key.toJS, response.clone()).toDart;
      }
      final blob = await response.blob().toDart;
      final objectUrl = web.URL.createObjectURL(blob);
      _objectUrls[key] = objectUrl;
      return NetworkImage(objectUrl);
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    for (final objectUrl in _objectUrls.values) {
      web.URL.revokeObjectURL(objectUrl);
    }
    _objectUrls.clear();
  }
}
