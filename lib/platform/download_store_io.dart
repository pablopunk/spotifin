import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class DownloadStore {
  Future<String> save(String accountId, String trackId, Uri source) async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory('${root.path}/downloads/$accountId');
    await directory.create(recursive: true);
    final target = File('${directory.path}/$trackId.audio');
    final temporary = File('${target.path}.partial');
    final response = await http.Client().send(http.Request('GET', source));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Download failed (${response.statusCode}).');
    }
    final sink = temporary.openWrite();
    await response.stream.pipe(sink);
    await temporary.rename(target.path);
    return target.uri.toString();
  }

  Future<Uri?> resolve(String storedUri) async {
    final uri = Uri.parse(storedUri);
    return await File.fromUri(uri).exists() ? uri : null;
  }

  Future<void> remove(String storedUri) async {
    final file = File.fromUri(Uri.parse(storedUri));
    if (await file.exists()) await file.delete();
  }
}
