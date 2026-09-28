import '../jellyfin/account_scope.dart';

/// Captured context guarding one Downtify effect.
///
/// Holds the account lease, the normalized origin URL, and the controller
/// lifecycle epoch captured before the effect's first await. After each
/// await the effect re-checks this scope before starting new work,
/// persisting rows, emitting notices, or rescheduling timers — never
/// choosing a URL or account from mutable state after an await.
class ImportScope {
  const ImportScope({
    required this.lease,
    required this.origin,
    required this.epoch,
  });

  final AccountLease lease;
  final String origin;
  final int epoch;
}
