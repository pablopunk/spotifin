import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'safe_path_segment.dart';

class ArtworkStore {
  final Map<String, Future<ImageProvider?>> _pending = {};

  Future<ImageProvider?> resolve(
    String accountId,
    String itemId,
    int width,
    Uri source,
  ) {
    final key = '$accountId:$itemId:$width';
    return _pending.putIfAbsent(key, () {
      final future = _resolve(accountId, itemId, width, source);
      future.whenComplete(() => _pending.remove(key));
      return future;
    });
  }

  Future<ImageProvider?> _resolve(
    String accountId,
    String itemId,
    int width,
    Uri source,
  ) async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(
      '${root.path}/artwork/${safePathSegment(accountId)}',
    );
    final target = File(
      '${directory.path}/${safePathSegment(itemId)}-$width.jpg',
    );
    if (await target.exists()) return FileImage(target);
    try {
      final response = await http
          .get(source)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      await directory.create(recursive: true);
      final temporary = File('${target.path}.partial');
      await temporary.writeAsBytes(response.bodyBytes, flush: true);
      await temporary.rename(target.path);
      return FileImage(target);
    } catch (_) {
      return null;
    }
  }

  void dispose() {}
}
