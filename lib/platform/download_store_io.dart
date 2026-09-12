import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'download_store_exception.dart';

class DownloadStore {
  Future<String> save(
    String accountId,
    String trackId,
    Uri source,
    Map<String, String> headers,
    String extension,
  ) async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}/downloads/$accountId');
    await directory.create(recursive: true);
    final safeExtension = extension.replaceAll(RegExp('[^a-zA-Z0-9]'), '');
    final target = File(
      '${directory.path}/$trackId.${safeExtension.isEmpty ? 'mp3' : safeExtension}',
    );
    final temporary = File('${target.path}.partial');
    final client = http.Client();
    try {
      if (await temporary.exists()) await temporary.delete();
      final request = http.Request('GET', source)..headers.addAll(headers);
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw DownloadStoreException(
          'Download failed (${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
      final sink = temporary.openWrite();
      await response.stream.timeout(const Duration(seconds: 30)).pipe(sink);
      if (await target.exists()) await target.delete();
      await temporary.rename(target.path);
      return target.uri.toString();
    } finally {
      client.close();
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<Uri?> resolve(String storedUri) async {
    final uri = Uri.parse(storedUri);
    return await File.fromUri(uri).exists() ? uri : null;
  }

  Future<void> remove(String storedUri) async {
    final file = File.fromUri(Uri.parse(storedUri));
    if (await file.exists()) await file.delete();
  }

  void dispose() {}
}
