import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'download_store_exception.dart';
import 'safe_path_segment.dart';

class DownloadStore {
  DownloadStore({
    http.Client Function()? clientFactory,
    IOSink Function(File file)? sinkFactory,
  }) : _clientFactory = clientFactory ?? (() => http.Client()),
       _sinkFactory = sinkFactory ?? ((file) => file.openWrite());

  static const _defaultTimeout = Duration(minutes: 5);

  final http.Client Function() _clientFactory;
  final IOSink Function(File file) _sinkFactory;
  final Map<(String, String), _IoTransfer> _active = {};
  final Map<(String, String), Future<void>> _startTails = {};
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
    final previousStart = _startTails[key];
    final startGate = Completer<void>();
    _startTails[key] = startGate.future;
    late final _IoTransfer transfer;
    late final Future<String> operation;
    try {
      if (previousStart != null) await previousStart;
      final previous = _active[key];
      if (previous != null) await previous.cancelAndWait();
      if (_disposed) {
        throw const DownloadStoreException('Download store is disposed.');
      }

      transfer = _IoTransfer(key, ++_nextOperationId, _clientFactory());
      _active[key] = transfer;
      operation = _save(transfer, source, headers, extension);
      transfer.completion = operation;
    } finally {
      if (identical(_startTails[key], startGate.future)) {
        _startTails.remove(key);
      }
      startGate.complete();
    }
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
    Future<void>? sinkDone;
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

      sink = _sinkFactory(temporary);
      transfer.sink = sink;
      final writeFailure = Completer<_IoWriteFailure>();
      sinkDone = sink.done.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          if (!transfer.cancelled && !writeFailure.isCompleted) {
            writeFailure.complete(_IoWriteFailure(error, stackTrace));
          }
        },
      );
      final iterator = StreamIterator<List<int>>(response.stream);
      transfer.iterator = iterator;
      try {
        _throwIfCancelled(transfer);
        while (await _raceWithSink(
          iterator.moveNext(),
          writeFailure.future,
          transfer,
        )) {
          _throwIfCancelled(transfer);
          sink.add(iterator.current);
          await _raceWithSink(
            sink.flush().then<void>((_) {}),
            writeFailure.future,
            transfer,
          );
        }
      } catch (error, stackTrace) {
        await transfer.stopBody();
        if (transfer.cancelled) _throwCancelled();
        Error.throwWithStackTrace(error, stackTrace);
      } finally {
        if (identical(transfer.iterator, iterator)) transfer.iterator = null;
      }
      _throwIfCancelled(transfer);

      await sink.flush();
      await sink.close();
      transfer.sink = null;
      sink = null;
      await sinkDone;
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
      transfer.closeClient();
      await transfer.stopBody();
      final activeSink = transfer.sink ?? sink;
      if (activeSink != null) {
        try {
          await activeSink.close();
        } catch (_) {}
      }
      transfer.sink = null;
      if (sinkDone != null) {
        try {
          await sinkDone;
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

  static Future<T> _raceWithSink<T>(
    Future<T> operation,
    Future<_IoWriteFailure> writeFailure,
    _IoTransfer transfer,
  ) async {
    final result = await Future.any<Object>([
      operation.then<Object>((value) => _IoOperationResult<T>(value)),
      writeFailure,
      transfer.cancelledSignal.future.then<Object>((_) => const _IoCancelled()),
    ]);
    if (result is _IoWriteFailure) {
      Error.throwWithStackTrace(result.error, result.stackTrace);
    }
    if (result is _IoCancelled) _throwCancelled();
    return (result as _IoOperationResult<T>).value;
  }

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
  final Completer<void> cancelledSignal = Completer<void>();
  bool cancelled = false;
  bool _clientClosed = false;
  IOSink? sink;
  StreamIterator<List<int>>? iterator;
  Future<String>? completion;
  Future<void>? _cancelFuture;
  Future<void>? _iteratorCancelFuture;

  void closeClient() {
    if (_clientClosed) return;
    _clientClosed = true;
    try {
      client.close();
    } catch (_) {}
  }

  Future<void> stopBody() async {
    closeClient();
    final currentIterator = iterator;
    if (currentIterator == null) return;
    try {
      await (_iteratorCancelFuture ??= currentIterator.cancel());
    } catch (_) {}
  }

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
    if (!cancelledSignal.isCompleted) cancelledSignal.complete();
    await stopBody();
  }
}

class _IoWriteFailure {
  const _IoWriteFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

class _IoOperationResult<T> {
  const _IoOperationResult(this.value);

  final T value;
}

class _IoCancelled {
  const _IoCancelled();
}
