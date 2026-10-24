import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'download_store_exception.dart';
import 'safe_path_segment.dart';

class DownloadStore {
  DownloadStore({http.Client Function()? clientFactory})
    : _clientFactory = clientFactory ?? (() => http.Client());

  static const _defaultTimeout = Duration(minutes: 5);

  final http.Client Function() _clientFactory;
  final Map<(String, String), _IoTransfer> _active = {};
  var _nextOperationId = 0;
  var _disposed = false;

  Future<String> save(
    String accountId,
    String trackId,
    Uri source,
    Map<String, String> headers,
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

    final transfer = _IoTransfer(key, ++_nextOperationId, _clientFactory());
    _active[key] = transfer;
    final operation = _save(transfer, source, headers, extension);
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
    _IoTransfer transfer,
    Uri source,
    Map<String, String> headers,
    String extension,
  ) async {
    File? temporary;
    File? backup;
    File? target;
    IOSink? sink;
    var installedTarget = false;
    try {
      final root = await getApplicationDocumentsDirectory();
      _throwIfCancelled(transfer);
      final directory = Directory(
        '${root.path}/downloads/${safePathSegment(transfer.key.$1)}',
      );
      await directory.create(recursive: true);
      final safeExtension = extension.replaceAll(RegExp('[^a-zA-Z0-9]'), '');
      target = File(
        '${directory.path}/${safePathSegment(transfer.key.$2)}.${safeExtension.isEmpty ? 'mp3' : safeExtension}',
      );
      temporary = File('${target.path}.${transfer.operationId}.partial');
      backup = File('${target.path}.${transfer.operationId}.backup');

      final request = http.Request('GET', source)..headers.addAll(headers);
      final response = await transfer.client.send(request);
      _throwIfCancelled(transfer);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw DownloadStoreException(
          'Download failed (${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }

      sink = temporary.openWrite();
      transfer.sink = sink;
      final bodyComplete = Completer<void>();
      transfer.bodyComplete = bodyComplete;
      transfer.subscription = response.stream.listen(
        (chunk) {
          if (!transfer.cancelled) sink!.add(chunk);
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!bodyComplete.isCompleted) {
            bodyComplete.completeError(error, stackTrace);
          }
        },
        onDone: () {
          if (!bodyComplete.isCompleted) bodyComplete.complete();
        },
        cancelOnError: true,
      );
      try {
        await bodyComplete.future;
      } catch (error) {
        if (transfer.cancelled) _throwCancelled();
        rethrow;
      }
      _throwIfCancelled(transfer);

      await sink.flush();
      await sink.close();
      transfer.sink = null;
      _throwIfCancelled(transfer);

      if (await target.exists()) {
        _throwIfCancelled(transfer);
        await target.rename(backup.path);
        _throwIfCancelled(transfer);
      }
      _throwIfCancelled(transfer);
      await temporary.rename(target.path);
      temporary = null;
      installedTarget = true;
      if (transfer.cancelled) _throwCancelled();
      if (await backup.exists()) await backup.delete();
      return target.uri.toString();
    } catch (_) {
      if (transfer.cancelled) {
        if (installedTarget && target != null && await target.exists()) {
          await target.delete();
        }
        if (backup != null && await backup.exists()) {
          await backup.rename(target!.path);
        }
        _throwCancelled();
      }
      rethrow;
    } finally {
      try {
        transfer.client.close();
      } catch (_) {}
      final activeSink = transfer.sink ?? sink;
      if (activeSink != null) {
        try {
          await activeSink.close();
        } catch (_) {}
      }
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
      if (backup != null && await backup.exists()) {
        if (target != null && !await target.exists()) {
          await backup.rename(target.path);
        } else {
          await backup.delete();
        }
      }
    }
  }

  static void _throwIfCancelled(_IoTransfer transfer) {
    if (transfer.cancelled) _throwCancelled();
  }

  static Never _throwCancelled() =>
      throw const DownloadStoreException('Download cancelled.');

  Future<Uri?> resolve(String storedUri) async {
    final uri = Uri.parse(storedUri);
    return await File.fromUri(uri).exists() ? uri : null;
  }

  Future<void> remove(String storedUri) async {
    final file = File.fromUri(Uri.parse(storedUri));
    if (await file.exists()) await file.delete();
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
  }
}

class _IoTransfer {
  _IoTransfer(this.key, this.operationId, this.client);

  final (String, String) key;
  final int operationId;
  final http.Client client;
  bool cancelled = false;
  IOSink? sink;
  StreamSubscription<List<int>>? subscription;
  Completer<void>? bodyComplete;
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
    try {
      client.close();
    } catch (_) {}
    final subscription = this.subscription;
    if (subscription != null) {
      try {
        await subscription.cancel();
      } catch (_) {}
    }
    final bodyComplete = this.bodyComplete;
    if (bodyComplete != null && !bodyComplete.isCompleted) {
      bodyComplete.complete();
    }
    final sink = this.sink;
    if (sink != null) {
      try {
        await sink.close();
      } catch (_) {}
    }
  }
}
