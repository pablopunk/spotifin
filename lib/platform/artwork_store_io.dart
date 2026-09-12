import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ArtworkStore {
  Future<ImageProvider?> resolve(
    String accountId,
    String itemId,
    int width,
    Uri source,
  ) async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory('${root.path}/artwork/${_safe(accountId)}');
    final target = File('${directory.path}/${_safe(itemId)}-$width.jpg');
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

  String _safe(String value) =>
      value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

  void dispose() {}
}
