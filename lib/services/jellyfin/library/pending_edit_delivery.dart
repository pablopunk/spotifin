import 'dart:convert';

import '../../../storage/database.dart';
import '../account_scope.dart';
import '../jellyfin_client.dart';

/// Outcome of delivering one pending operation.
enum PendingDelivery { delivered, blocked, stale }

/// Internal delivery implementation for [JellyfinLibrary].
///
/// Delivers a single currently-pending operation at a time. The library
/// module owns the server lane, drain joining, and wake-ups; this class
/// only reads the next operation immediately before delivery, performs one
/// request, and acknowledges exactly the completed operation id.
class PendingEditDelivery {
  PendingEditDelivery(this._client, this._database, this._scope);

  final JellyfinClient _client;
  final AppDatabase _database;
  final AccountScope _scope;

  /// Delivers the next pending operation in rowid insertion order.
  ///
  /// Re-checks the lease and the operation's existence before starting the
  /// request: an operation already sent cannot be cancelled merely because
  /// it was later coalesced, but a removed operation is skipped. Only the
  /// completed operation id is acknowledged, so completing favorite A never
  /// removes a newer favorite B. Failures increment attempts once and
  /// report blocked without spinning; unknown kinds stay pending and
  /// report blocked. Stale leases acknowledge nothing.
  Future<PendingDelivery> deliverNext(AccountLease lease) async {
    if (!_scope.isCurrent(lease)) return PendingDelivery.stale;
    final queued = await _database.nextPendingOperation();
    if (queued == null) return PendingDelivery.delivered;
    if (!_scope.isCurrent(lease)) return PendingDelivery.stale;
    final operation = await _database.pendingOperationById(queued.id);
    if (operation == null) return PendingDelivery.delivered;
    if (!_scope.isCurrent(lease)) return PendingDelivery.stale;
    try {
      await _send(lease, operation);
    } catch (_) {
      if (!_scope.isCurrent(lease)) return PendingDelivery.stale;
      try {
        await _database.incrementPendingAttempts(operation.id);
      } catch (_) {}
      return PendingDelivery.blocked;
    }
    if (!_scope.isCurrent(lease)) return PendingDelivery.stale;
    await _database.completePending(operation.id);
    return PendingDelivery.delivered;
  }

  Future<void> _send(AccountLease lease, PendingWrite operation) async {
    final session = lease.session;
    switch (operation.kind) {
      case 'favorite':
        final payload = _payload(operation);
        await _client.setFavorite(
          session,
          operation.targetId,
          payload['favorite'] as bool,
        );
      case 'playlistAdd':
        final payload = _payload(operation);
        await _client.addToPlaylist(session, operation.targetId, [
          payload['trackId'] as String,
        ]);
      default:
        // Unknown kinds stay pending; the drain reports them blocked.
        throw StateError('Unknown pending kind ${operation.kind}');
    }
  }

  Map<String, dynamic> _payload(PendingWrite operation) {
    try {
      return jsonDecode(operation.payload) as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException('Undecodable pending payload');
    }
  }
}
