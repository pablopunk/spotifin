import 'dart:async';

import 'package:flutter/foundation.dart';

import 'session.dart';

/// Normalized owner key for a session: `serverUrl|serverId|userId`.
///
/// The server URL is normalized (trimmed, lower-cased scheme/host, no
/// trailing slash) so the same Jellyfin account entered with cosmetic URL
/// differences still maps to one owner. Contains no token or display name.
String normalizeServerUrlForOwner(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  final candidate = trimmed.contains('://') ? trimmed : 'https://$trimmed';
  final uri = Uri.tryParse(candidate);
  if (uri == null || uri.host.isEmpty) return trimmed.toLowerCase();
  final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}$port$path';
}

/// Stable cache-owner key for [session].
String accountOwnerKeyForSession(JellyfinSession session) =>
    '${normalizeServerUrlForOwner(session.serverUrl)}|${session.serverId}|${session.userId}';

/// Immutable capture of the active account at one point in time.
///
/// [generation] comes from [AccountScope]; [ownerKey] is
/// [accountOwnerKeyForSession] for [session]. Leases are compared by
/// generation and owner, never by object identity, so an ordinary identity
/// refresh (same owner, same generation) keeps existing subscriptions valid.
@immutable
class AccountLease {
  const AccountLease({
    required this.session,
    required this.generation,
    required this.ownerKey,
  });

  final JellyfinSession session;
  final int generation;
  final String ownerKey;
}

/// Explicit outcome of a fenced local write.
///
/// Stale work is reported as [stale], never disguised as successful data.
enum AccountWriteResult { applied, stale }

/// Guards account work and serializes local persistence.
///
/// The fence contains local persistence only, never HTTP or native audio
/// work. Already-started writes may finish; clearing runs after them because
/// every mutation is queued on the same [_tail]. Callers must still check
/// [isCurrent] after an awaited fence before publishing state, enqueueing
/// effects, acknowledging edits, or reviving timers.
///
/// Never acquire the fence recursively (awaiting [commit]/[exclusive] from
/// inside fenced work deadlocks); a [StateError] is thrown in debug and
/// release to fail fast instead of hanging.
class AccountScope extends ChangeNotifier {
  int _generation = 0;
  AccountLease? _current;
  Future<void> _tail = Future.value();
  bool _inFence = false;

  /// Currently active lease, or null after [invalidate].
  AccountLease? get current => _current;

  /// Monotonic generation; bumped by [activate] and [invalidate].
  int get generation => _generation;

  /// True when [lease] names the currently active account.
  ///
  /// Compares generation and owner key, not object identity, so a lease
  /// captured before an identity refresh stays current afterwards.
  bool isCurrent(AccountLease? lease) {
    if (lease == null) return false;
    final current = _current;
    if (current == null) return false;
    return lease.generation == _generation &&
        lease.generation == current.generation &&
        lease.ownerKey == current.ownerKey;
  }

  /// Makes [session] the active account and returns its lease.
  ///
  /// Synchronous so subscribers observe the new account before any awaited
  /// setup runs.
  AccountLease activate(JellyfinSession session) {
    _generation++;
    _current = AccountLease(
      session: session,
      generation: _generation,
      ownerKey: accountOwnerKeyForSession(session),
    );
    notifyListeners();
    return _current!;
  }

  /// Clears the active lease and notifies synchronously.
  ///
  /// Must be called before any awaited teardown so late completions can
  /// observe the invalidation and stay silent.
  void invalidate() {
    _generation++;
    _current = null;
    notifyListeners();
  }

  /// Replaces same-owner session metadata without changing the generation.
  ///
  /// Returns the new immutable lease. Throws [StateError] when [lease] is
  /// stale or when [session] names a different owner; an owner change needs
  /// the explicit conflict flow, never a silent lease swap.
  AccountLease updateSession(AccountLease lease, JellyfinSession session) {
    if (!isCurrent(lease)) {
      throw StateError('Stale account lease');
    }
    final nextKey = accountOwnerKeyForSession(session);
    if (nextKey != lease.ownerKey) {
      throw StateError('Account owner changed');
    }
    _current = AccountLease(
      session: session,
      generation: lease.generation,
      ownerKey: lease.ownerKey,
    );
    notifyListeners();
    return _current!;
  }

  /// Runs [write] after previously queued fence work, only if [lease] is
  /// still current when the write starts.
  ///
  /// Returns [AccountWriteResult.applied] when [write] ran and
  /// [AccountWriteResult.stale] when [lease] was already invalidated (the
  /// write is skipped). Errors from [write] complete the returned future
  /// with an error; the fence itself stays usable.
  Future<AccountWriteResult> commit(
    AccountLease lease,
    Future<void> Function() write,
  ) {
    if (_inFence) {
      throw StateError('AccountScope fence cannot be acquired recursively');
    }
    final previous = _tail;
    final completer = Completer<AccountWriteResult>();
    _tail = previous.then((_) async {
      if (!isCurrent(lease)) {
        completer.complete(AccountWriteResult.stale);
        return;
      }
      _inFence = true;
      try {
        await write();
        completer.complete(AccountWriteResult.applied);
      } catch (error, stack) {
        completer.completeError(error, stack);
      } finally {
        _inFence = false;
      }
    });
    return completer.future;
  }

  /// Runs [work] after previously queued fence work, without a lease.
  ///
  /// Use for startup token migration, account clearing, owner-marker
  /// persistence, and activation commits. Callers that activate an account
  /// must capture [generation] before enqueueing and re-check it inside
  /// [work] so a queued activation cannot revive an invalidated account.
  Future<T> exclusive<T>(Future<T> Function() work) {
    if (_inFence) {
      throw StateError('AccountScope fence cannot be acquired recursively');
    }
    final previous = _tail;
    final completer = Completer<T>();
    _tail = previous.then((_) async {
      _inFence = true;
      try {
        completer.complete(await work());
      } catch (error, stack) {
        completer.completeError(error, stack);
      } finally {
        _inFence = false;
      }
    });
    return completer.future;
  }
}
