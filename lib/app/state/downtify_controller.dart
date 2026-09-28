import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/downtify/downtify_client.dart';
import '../../services/downtify/downtify_matcher.dart';
import '../../services/downtify/downtify_models.dart';
import '../../services/downtify/import_policy.dart';
import '../../services/downtify/import_scheduler.dart';
import '../../services/downtify/import_scope.dart';
import '../../services/jellyfin/account_scope.dart';
import '../../services/jellyfin/jellyfin_client.dart';
import '../../services/redaction.dart';
import '../../storage/database.dart';
import '../providers.dart';

enum DowntifyAvailability { loading, unconfigured, available, unavailable }

class DowntifyNotice {
  const DowntifyNotice(this.id, this.message, {this.error = false});

  final String id;
  final String message;
  final bool error;
}

class DowntifyState {
  const DowntifyState({
    this.availability = DowntifyAvailability.loading,
    this.serverUrl,
    this.version,
    this.results = const [],
    this.searching = false,
    this.imports = const [],
    this.notices = const [],
    this.searchNonce = 0,
  });

  final DowntifyAvailability availability;
  final String? serverUrl;
  final String? version;
  final List<DowntifySong> results;
  final bool searching;
  final List<DowntifyImport> imports;
  final List<DowntifyNotice> notices;

  /// Bumped whenever the query view must clear (configure, removal,
  /// account change).
  final int searchNonce;

  bool get available => availability == DowntifyAvailability.available;

  DowntifyState copyWith({
    DowntifyAvailability? availability,
    String? serverUrl,
    String? version,
    List<DowntifySong>? results,
    bool? searching,
    List<DowntifyImport>? imports,
    List<DowntifyNotice>? notices,
    int? searchNonce,
    bool clearServer = false,
  }) => DowntifyState(
    availability: availability ?? this.availability,
    serverUrl: clearServer ? null : serverUrl ?? this.serverUrl,
    version: clearServer ? null : version ?? this.version,
    results: results ?? this.results,
    searching: searching ?? this.searching,
    imports: imports ?? this.imports,
    notices: notices ?? this.notices,
    searchNonce: searchNonce ?? this.searchNonce,
  );
}

class DowntifyController extends Notifier<DowntifyState> {
  static const maxDownloadRetries = 3;

  static const _searchDebounce = Duration(milliseconds: 300);
  static const _scanDebounce = Duration(seconds: 1);
  static const _pollInterval = Duration(seconds: 2);
  static const _catalogInterval = Duration(seconds: 10);

  late AccountScope _scope;
  late ImportScheduler _scheduler;
  bool _disposed = false;

  /// Lifecycle epoch invalidating in-flight work. Bumped synchronously on
  /// configure, integration removal, account invalidation or replacement,
  /// and disposal — always before the first await of the triggering call.
  int _epoch = 0;

  Timer? _searchTimer;
  Timer? _pollTimer;
  Timer? _scanTimer;
  int _searchGeneration = 0;
  int? _pollLockEpoch;
  int? _catalogLockEpoch;
  int _pollFailures = 0;
  DateTime? _lastJellyfinRefresh;

  /// Per-import attempt tokens. Retry and removal invalidate the token
  /// before waiting; poll and scan batches capture tokens before their
  /// request so old responses cannot touch a replacement attempt reusing
  /// the same row id.
  final Map<String, int> _attempts = {};
  int _attemptSeq = 0;

  /// Serialized config-store writes: the latest configure/removal wins.
  Future<void> _configChain = Future.value();

  /// Scan-batch row ids captured before the scan request.
  List<String> _scanBatchIds = const [];

  @override
  DowntifyState build() {
    _scope = ref.watch(accountScopeProvider);
    _scheduler = ref.watch(importSchedulerProvider);
    _scope.removeListener(_onAccountChanged);
    _scope.addListener(_onAccountChanged);
    ref.onDispose(() {
      _disposed = true;
      _epoch++;
      _scope.removeListener(_onAccountChanged);
      _searchTimer?.cancel();
      _pollTimer?.cancel();
      _pollTimer = null;
      _scanTimer?.cancel();
      _pollLockEpoch = null;
      _catalogLockEpoch = null;
    });
    Future.microtask(_initialize);
    return const DowntifyState();
  }

  // ------------------------------------------------------------------
  // Scope, epoch, and attempt guards.
  // ------------------------------------------------------------------

  /// Captures the effect context before its first await: the account lease,
  /// the normalized origin URL, and the lifecycle epoch.
  ImportScope? _captureScope() {
    final lease = _scope.current;
    final origin = state.serverUrl;
    if (lease == null || origin == null || origin.isEmpty) return null;
    return ImportScope(lease: lease, origin: origin, epoch: _epoch);
  }

  bool _scopeValid(ImportScope scope) =>
      !_disposed &&
      scope.epoch == _epoch &&
      _scope.isCurrent(scope.lease) &&
      state.serverUrl == scope.origin;

  bool _attemptCurrent(String id, int attempt) {
    final current = _attempts[id];
    // Rows without a recorded attempt were never superseded; only an
    // explicitly invalidated (bumped) token defeats an older one.
    return current == null || current == attempt;
  }

  /// Invalidates the row's previous attempt before waiting on new work.
  int _beginAttempt(String id) {
    final attempt = ++_attemptSeq;
    _attempts[id] = attempt;
    return attempt;
  }

  void _cancelAllWork() {
    _searchTimer?.cancel();
    _searchTimer = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _scanTimer?.cancel();
    _scanTimer = null;
    _pollLockEpoch = null;
    _catalogLockEpoch = null;
  }

  void _onAccountChanged() {
    if (_disposed) return;
    _epoch++;
    _cancelAllWork();
    final lease = _scope.current;
    state = state.copyWith(
      searchNonce: state.searchNonce + 1,
      results: const [],
      searching: false,
    );
    if (lease == null) {
      // No account: clear the import view without sending old rows to a
      // new origin. Stored rows stay for later.
      state = state.copyWith(imports: const []);
      return;
    }
    Future.microtask(() => _handleAccountAvailable(lease));
  }

  Future<void> _handleAccountAvailable(AccountLease lease) async {
    try {
      await _loadImports(lease);
      if (_disposed || !_scope.isCurrent(lease)) return;
      await _recoverSavedImports();
    } catch (_) {}
  }

  Future<void> _writeConfig(int epoch, Future<void> Function() write) {
    final previous = _configChain;
    final completer = Completer<void>();
    _configChain = previous.then((_) async {
      if (epoch != _epoch || _disposed) {
        completer.complete();
        return;
      }
      try {
        await write();
        completer.complete();
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  void _bumpSearchNonce() {
    if (_disposed) return;
    state = state.copyWith(searchNonce: state.searchNonce + 1);
  }

  // ------------------------------------------------------------------
  // Lifecycle.
  // ------------------------------------------------------------------

  Future<void> _initialize() async {
    final serverUrl = await ref.read(downtifyStoreProvider).loadServerUrl();
    if (_disposed) return;
    if (serverUrl == null) {
      state = state.copyWith(
        availability: DowntifyAvailability.unconfigured,
        clearServer: true,
      );
      return;
    }
    await _connect(serverUrl);
    if (_disposed) return;
    if (_scope.current != null) {
      await _loadImports(_scope.current);
      await _recoverSavedImports();
    }
  }

  Future<void> configure(String value) async {
    final origin = DowntifyClient.normalizeServerUrl(value);
    _epoch++;
    final epoch = _epoch;
    _cancelAllWork();
    _bumpSearchNonce();
    state = state.copyWith(
      availability: DowntifyAvailability.loading,
      serverUrl: origin,
      results: const [],
    );
    try {
      final version = await ref
          .read(downtifyClientProvider)
          .fetchVersion(origin);
      if (epoch != _epoch || _disposed) return;
      await _writeConfig(
        epoch,
        () => ref.read(downtifyStoreProvider).saveServerUrl(origin),
      );
      if (epoch != _epoch || _disposed) return;
      state = state.copyWith(
        availability: DowntifyAvailability.available,
        serverUrl: origin,
        version: version,
      );
    } catch (_) {
      if (epoch != _epoch || _disposed) return;
      state = state.copyWith(availability: DowntifyAvailability.unavailable);
      rethrow;
    }
    if (epoch != _epoch || _disposed) return;
    await _loadImports(_scope.current);
    if (epoch != _epoch || _disposed) return;
    await _recoverSavedImports();
    if (epoch != _epoch || _disposed) return;
    _startPolling();
  }

  Future<void> reconnect() async {
    final epoch = _epoch;
    final serverUrl = state.serverUrl;
    if (serverUrl != null) await _connect(serverUrl);
    if (epoch != _epoch || _disposed) return;
  }

  Future<void> removeConfiguration() async {
    _epoch++;
    final epoch = _epoch;
    _cancelAllWork();
    await _writeConfig(
      epoch,
      () => ref.read(downtifyStoreProvider).clearServerUrl(),
    );
    if (epoch != _epoch || _disposed) return;
    _bumpSearchNonce();
    // Configuration removal keeps stored rows; only the view resets.
    state = const DowntifyState(
      availability: DowntifyAvailability.unconfigured,
    );
  }

  Future<void> _connect(String serverUrl) async {
    final epoch = _epoch;
    state = state.copyWith(
      availability: DowntifyAvailability.loading,
      serverUrl: serverUrl,
    );
    try {
      final version = await ref
          .read(downtifyClientProvider)
          .fetchVersion(serverUrl);
      if (epoch != _epoch || _disposed) return;
      state = state.copyWith(
        availability: DowntifyAvailability.available,
        version: version,
      );
      _startPolling();
      await poll();
    } catch (_) {
      if (epoch != _epoch || _disposed) return;
      state = state.copyWith(availability: DowntifyAvailability.unavailable);
    }
  }

  // ------------------------------------------------------------------
  // Search (controller-owned, debounced, scoped).
  // ------------------------------------------------------------------

  void search(String query) {
    final epoch = _epoch;
    _searchTimer?.cancel();
    final trimmed = query.trim();
    final generation = ++_searchGeneration;
    if (trimmed.length < 2) {
      state = state.copyWith(results: const [], searching: false);
      return;
    }
    state = state.copyWith(searching: true);
    _searchTimer = _scheduler.schedule(_searchDebounce, () async {
      if (epoch != _epoch || generation != _searchGeneration || _disposed) {
        return;
      }
      final origin = state.serverUrl;
      if (origin == null) {
        state = state.copyWith(results: const [], searching: false);
        return;
      }
      try {
        final results = await ref
            .read(downtifyClientProvider)
            .search(origin, trimmed);
        if (epoch != _epoch ||
            generation != _searchGeneration ||
            _disposed ||
            state.serverUrl != origin) {
          return;
        }
        state = state.copyWith(results: results, searching: false);
      } catch (_) {
        if (epoch != _epoch || generation != _searchGeneration || _disposed) {
          return;
        }
        state = state.copyWith(
          availability: DowntifyAvailability.unavailable,
          results: const [],
          searching: false,
        );
      }
    });
  }

  // ------------------------------------------------------------------
  // Imports.
  // ------------------------------------------------------------------

  Future<void> enqueue(DowntifySong song) async {
    final scope = _captureScope();
    if (scope == null) return;
    final session = scope.lease.session;
    if (importFor(song.id) != null) return;
    final now = _scheduler.now();
    final id = '${session.serverId}:${session.userId}:${song.id}';
    final occupied = await ref.read(databaseProvider).getDowntifyImport(id);
    if (occupied != null) return;
    var created = false;
    await _scope.commit(scope.lease, () async {
      if (!_scope.isCurrent(scope.lease)) return;
      final raced = await ref.read(databaseProvider).getDowntifyImport(id);
      if (raced != null) return;
      await ref
          .read(databaseProvider)
          .putDowntifyImport(
            DowntifyImportsCompanion.insert(
              id: id,
              jellyfinServerId: session.serverId,
              jellyfinUserId: session.userId,
              downtifyUrl: scope.origin,
              externalSongId: song.id,
              songJson: jsonEncode(song.raw),
              status: 'submitting',
              createdAt: now,
              updatedAt: now,
            ),
          );
      created = true;
    });
    if (!created || !_scopeValid(scope)) return;
    await _loadImports(scope.lease);
    if (!_scopeValid(scope)) return;
    final attempt = _beginAttempt(id);
    try {
      final jobId = await ref
          .read(downtifyClientProvider)
          .enqueue(scope.origin, song);
      if (!_scopeValid(scope) || !_attemptCurrent(id, attempt)) return;
      await _updateExisting(
        scope,
        id,
        attempt,
        DowntifyImportsCompanion(
          status: const Value('queued'),
          jobId: Value(jobId),
        ),
      );
      _startPolling();
      await poll();
    } catch (error) {
      if (!_scopeValid(scope) || !_attemptCurrent(id, attempt)) return;
      await _updateExisting(
        scope,
        id,
        attempt,
        DowntifyImportsCompanion(
          status: const Value('downloadFailed'),
          message: Value(redactSecrets(error)),
        ),
      );
      _addNotice('Import failed for ${song.name}.', error: true);
    }
  }

  /// Finds the current account's row for an external song, including rows
  /// from another origin, so a new enqueue cannot overwrite one silently.
  DowntifyImport? importFor(String externalSongId) {
    final lease = _scope.current;
    if (lease == null) return null;
    final session = lease.session;
    return state.imports.where((item) {
      return item.externalSongId == externalSongId &&
          item.jellyfinServerId == session.serverId &&
          item.jellyfinUserId == session.userId;
    }).firstOrNull;
  }

  /// Manual retry of a terminal failure: invalidates the old attempt, then
  /// creates a fresh attempt at the currently selected URL with a current
  /// timestamp and zero retry count.
  Future<void> retry(DowntifyImport item) async {
    _beginAttempt(item.id);
    final scope = _captureScope();
    if (scope == null) return;
    final attempt = _attempts[item.id]!;
    await _guardedRowRemove(scope, item.id, attempt, origin: item.downtifyUrl);
    if (!_scopeValid(scope)) return;
    await _loadImports(scope.lease);
    await enqueue(_songFromImport(item));
  }

  /// Local dismissal of an imported row.
  Future<void> dismiss(DowntifyImport item) async {
    final attempt = _beginAttempt(item.id);
    final scope = _captureScope();
    if (scope == null) return;
    await _guardedRowRemove(scope, item.id, attempt, origin: item.downtifyUrl);
    if (!_scopeValid(scope)) return;
    await _loadImports(scope.lease);
  }

  /// Remote removal always targets the row's original URL. A successful
  /// removal response, including `removed:false`, removes the local row; a
  /// failed removal retains it and reports the existing redacted error.
  Future<void> removeFromQueue(DowntifyImport item) async {
    final attempt = _beginAttempt(item.id);
    final scope = _captureScope();
    if (scope == null) return;
    try {
      await ref
          .read(downtifyClientProvider)
          .removeQueueItem(item.downtifyUrl, item.jobId ?? item.externalSongId);
    } catch (error) {
      if (!_scopeValid(scope) || !_attemptCurrent(item.id, attempt)) return;
      _addNotice(
        'Could not remove ${_songFromImport(item).name}: ${redactSecrets(error)}',
        error: true,
      );
      return;
    }
    if (!_scopeValid(scope) || !_attemptCurrent(item.id, attempt)) return;
    await _guardedRowRemove(scope, item.id, attempt, origin: item.downtifyUrl);
    if (!_scopeValid(scope)) return;
    await _loadImports(scope.lease);
  }

  void dismissNotice(String id) {
    state = state.copyWith(
      notices: state.notices.where((notice) => notice.id != id).toList(),
    );
  }

  // ------------------------------------------------------------------
  // Polling.
  // ------------------------------------------------------------------

  Future<void> poll() async {
    final epoch = _epoch;
    final origin = state.serverUrl;
    if (origin == null || _disposed) return;
    if (_pollLockEpoch != null) return;
    _pollLockEpoch = epoch;
    try {
      List<DowntifyJob>? remote;
      try {
        remote = await ref.read(downtifyClientProvider).fetchQueue(origin);
      } catch (_) {
        // A failed queue request is not evidence of absence: catalog
        // checks still run below.
        if (epoch != _epoch || _disposed) return;
        _pollFailures++;
        state = state.copyWith(availability: DowntifyAvailability.unavailable);
        await _refreshWaitingImports();
        return;
      }
      if (epoch != _epoch || _disposed) return;
      _pollFailures = 0;
      if (!state.available) {
        state = state.copyWith(availability: DowntifyAvailability.available);
      }
      final scope = _captureScope();
      final tokens = Map<String, int>.of(_attempts);
      final jobs = remote;
      for (final item in [...state.imports]) {
        if (epoch != _epoch || _disposed) return;
        // Imports from another origin stay visible but paused: no
        // automatic work runs on them.
        if (item.downtifyUrl != origin) continue;
        final parsed = parseImportStatus(item.status);
        // Terminal eligibility applies before any remote error or
        // progress event; unknown rows stay inert.
        if (isTerminalImport(parsed) || parsed.kind == ImportStatus.unknown) {
          continue;
        }
        if (scope == null || !_scopeValid(scope)) continue;
        if (_attempts[item.id] != tokens[item.id]) continue;
        await _processPolledRow(
          scope,
          item,
          tokens[item.id] ?? -1,
          jobs,
          parsed,
        );
      }
      await _refreshWaitingImports();
    } finally {
      if (_pollLockEpoch == epoch) _pollLockEpoch = null;
    }
  }

  Future<void> _processPolledRow(
    ImportScope scope,
    DowntifyImport item,
    int attempt,
    List<DowntifyJob> remote,
    ParsedImportStatus saved,
  ) async {
    switch (saved.kind) {
      case ImportStatus.submitting:
      case ImportStatus.retrying:
        final job = matchImportJob(
          remote,
          storedJobId: item.jobId,
          externalSongId: item.externalSongId,
        );
        if (job == null || job.status == DowntifyJobStatus.unknown) {
          await _markInterrupted(scope, item, attempt);
        } else if (job.status == DowntifyJobStatus.done) {
          await _beginScan(scope, item, attempt, job);
        } else if (job.status == DowntifyJobStatus.error) {
          await _handleDownloadFailure(scope, item, attempt, job);
        } else {
          await _adoptRemoteProgress(scope, item, attempt, job);
        }
      case ImportStatus.queued:
      case ImportStatus.downloading:
        final job = matchImportJob(
          remote,
          storedJobId: item.jobId,
          externalSongId: item.externalSongId,
        );
        // Missing or unknown jobs never trigger resubmission.
        if (job == null || job.status == DowntifyJobStatus.unknown) return;
        if (job.status == DowntifyJobStatus.error) {
          await _handleDownloadFailure(scope, item, attempt, job);
        } else if (job.status == DowntifyJobStatus.done) {
          await _beginScan(scope, item, attempt, job);
        } else {
          await _adoptRemoteProgress(scope, item, attempt, job);
        }
      case ImportStatus.requestingScan:
      case ImportStatus.waitingForJellyfin:
      case ImportStatus.scanDenied:
      case ImportStatus.imported:
      case ImportStatus.downloadFailed:
      case ImportStatus.importTimedOut:
      case ImportStatus.unknown:
        return;
    }
  }

  Future<void> _adoptRemoteProgress(
    ImportScope scope,
    DowntifyImport item,
    int attempt,
    DowntifyJob job,
  ) async {
    await _updateExisting(
      scope,
      item.id,
      attempt,
      DowntifyImportsCompanion(
        status: Value(job.status.name),
        progress: Value(job.progress),
        message: Value(job.message),
        updatedAt: Value(_scheduler.now()),
      ),
    );
  }

  Future<void> _beginScan(
    ImportScope scope,
    DowntifyImport item,
    int attempt,
    DowntifyJob job,
  ) async {
    final applied = await _updateExisting(
      scope,
      item.id,
      attempt,
      DowntifyImportsCompanion(
        status: const Value('requestingScan'),
        progress: const Value(100.0),
        filename: Value(job.filename),
        updatedAt: Value(_scheduler.now()),
      ),
    );
    if (applied) _scheduleScanBatch();
  }

  Future<void> _markInterrupted(
    ImportScope scope,
    DowntifyImport item,
    int attempt,
  ) async {
    final applied = await _updateExisting(
      scope,
      item.id,
      attempt,
      DowntifyImportsCompanion(
        status: const Value('downloadFailed'),
        message: const Value(
          'Download interrupted before the server confirmed it. '
          'Retry manually to try again.',
        ),
        messageShown: const Value(true),
        updatedAt: Value(_scheduler.now()),
      ),
    );
    // Reloads never replay notices for rows already reported in a
    // previous session.
    if (applied && !item.messageShown) {
      _addNotice(
        'Import failed for ${_songName(item)}. Please retry it manually.',
        error: true,
      );
    }
  }

  Future<void> _handleDownloadFailure(
    ImportScope scope,
    DowntifyImport item,
    int attempt,
    DowntifyJob job,
  ) async {
    final current = _currentRow(item.id) ?? item;
    if (current.status == 'downloadFailed') return;
    if (current.retryCount >= maxDownloadRetries) {
      final applied = await _updateExisting(
        scope,
        item.id,
        attempt,
        DowntifyImportsCompanion(
          status: const Value('downloadFailed'),
          progress: Value(job.progress),
          message: Value(job.message),
          messageShown: const Value(true),
          updatedAt: Value(_scheduler.now()),
        ),
      );
      if (applied && !current.messageShown) {
        _addNotice('Import failed for ${job.song.name}.', error: true);
      }
      return;
    }
    var progressed = await _updateExisting(
      scope,
      item.id,
      attempt,
      DowntifyImportsCompanion(
        status: const Value('retrying'),
        progress: const Value(0.0),
        message: const Value('Retrying download…'),
        retryCount: Value(current.retryCount + 1),
        updatedAt: Value(_scheduler.now()),
      ),
    );
    if (!progressed) return;
    try {
      final client = ref.read(downtifyClientProvider);
      await client.removeQueueItem(
        scope.origin,
        current.jobId ?? current.externalSongId,
      );
      final jobId = await client.enqueue(
        scope.origin,
        _songFromImport(current),
      );
      await _updateExisting(
        scope,
        item.id,
        attempt,
        DowntifyImportsCompanion(
          status: const Value('queued'),
          jobId: Value(jobId),
          message: const Value(''),
          updatedAt: Value(_scheduler.now()),
        ),
      );
    } catch (error) {
      await _updateExisting(
        scope,
        item.id,
        attempt,
        DowntifyImportsCompanion(
          status: const Value('queued'),
          message: Value(redactSecrets(error)),
          updatedAt: Value(_scheduler.now()),
        ),
      );
    }
  }

  // ------------------------------------------------------------------
  // Poll scheduling.
  // ------------------------------------------------------------------

  void _startPolling() {
    _pollTimer?.cancel();
    _pollFailures = 0;
    _schedulePoll(_pollInterval);
  }

  void _schedulePoll(Duration delay) {
    _pollTimer?.cancel();
    final epoch = _epoch;
    _pollTimer = _scheduler.schedule(delay, () async {
      if (epoch != _epoch || _disposed) return;
      await poll();
      if (epoch != _epoch || _disposed) return;
      if (_pollTimer == null || state.serverUrl == null) return;
      final failures = _pollFailures > 5 ? 5 : _pollFailures;
      final seconds = failures == 0 ? 2 : 1 << failures;
      _schedulePoll(Duration(seconds: seconds > 30 ? 30 : seconds));
    });
  }

  // ------------------------------------------------------------------
  // Scan batches.
  // ------------------------------------------------------------------

  void _scheduleScanBatch() {
    _scanTimer?.cancel();
    final epoch = _epoch;
    _scanTimer = _scheduler.schedule(_scanDebounce, () async {
      if (epoch != _epoch || _disposed) return;
      await _runScanBatch(epoch);
    });
  }

  Future<void> _runScanBatch(int epoch) async {
    final scope = _captureScope();
    if (scope == null || epoch != _epoch || _disposed) return;
    final batchIds = state.imports
        .where(
          (item) =>
              item.status == 'requestingScan' &&
              item.downtifyUrl == scope.origin,
        )
        .map((item) => item.id)
        .toList();
    if (batchIds.isEmpty) return;
    _scanBatchIds = List.of(batchIds);
    try {
      await ref
          .read(jellyfinClientProvider)
          .requestLibraryRefresh(scope.lease.session);
    } on JellyfinException catch (error) {
      if (!_scopeValid(scope)) return;
      final denied = error.statusCode == 403;
      for (final id in _scanBatchIds) {
        if (!_scopeValid(scope)) return;
        await _updateExisting(
          scope,
          id,
          _attempts[id] ?? -1,
          DowntifyImportsCompanion(
            status: Value(denied ? 'scanDenied' : 'waitingForJellyfin'),
            message: Value(
              denied
                  ? 'Waiting for Jellyfin’s scheduled library scan.'
                  : redactSecrets(error),
            ),
            updatedAt: Value(_scheduler.now()),
          ),
        );
      }
      if (denied) {
        _addNotice(
          'Jellyfin did not allow an instant scan; the song will appear after its next scheduled scan.',
        );
      }
      _scheduleScanFollowUp(scope);
      return;
    } catch (_) {
      if (!_scopeValid(scope)) return;
      _scheduleScanFollowUp(scope);
      return;
    }
    if (!_scopeValid(scope)) return;
    for (final id in _scanBatchIds) {
      if (!_scopeValid(scope)) return;
      await _updateExisting(
        scope,
        id,
        _attempts[id] ?? -1,
        DowntifyImportsCompanion(
          status: const Value('waitingForJellyfin'),
          updatedAt: Value(_scheduler.now()),
        ),
      );
    }
    _scheduleScanFollowUp(scope);
  }

  /// Arrivals during a scan request need a follow-up batch, not a false
  /// successful-scan transition for rows the request never covered.
  void _scheduleScanFollowUp(ImportScope scope) {
    if (!_scopeValid(scope)) return;
    final arrived = state.imports.any(
      (item) =>
          item.status == 'requestingScan' &&
          item.downtifyUrl == scope.origin &&
          !_scanBatchIds.contains(item.id),
    );
    if (arrived) _scheduleScanBatch();
  }

  // ------------------------------------------------------------------
  // Waiting-import catalog checks.
  // ------------------------------------------------------------------

  Future<void> _refreshWaitingImports() async {
    if (_catalogLockEpoch != null || _disposed) return;
    final epoch = _epoch;
    final origin = state.serverUrl;
    if (origin == null) return;
    final waiting = state.imports.where((item) {
      return item.downtifyUrl == origin &&
          const {'waitingForJellyfin', 'scanDenied'}.contains(item.status);
    }).toList();
    if (waiting.isEmpty) return;
    final now = _scheduler.now();
    if (_lastJellyfinRefresh != null &&
        now.difference(_lastJellyfinRefresh!) < _catalogInterval) {
      return;
    }
    _lastJellyfinRefresh = now;
    _catalogLockEpoch = epoch;
    try {
      final scope = _captureScope();
      if (scope == null || scope.origin != origin) return;
      final result = await ref
          .read(jellyfinLibraryProvider)
          .refreshTracks(scope.lease);
      if (!_scopeValid(scope)) return;
      if (!result.isCommitted) return;
      final tracks = result.catalog;
      for (final item in waiting) {
        if (!_scopeValid(scope)) return;
        final current = _currentRow(item.id);
        if (current == null) continue;
        final song = _songFromImport(current);
        final match = const DowntifyMatcher().findMatch(song, tracks);
        if (match != null) {
          final applied = await _updateExisting(
            scope,
            item.id,
            _attempts[item.id] ?? -1,
            DowntifyImportsCompanion(
              status: const Value('imported'),
              matchedTrackId: Value(match.id),
              progress: const Value(100.0),
              updatedAt: Value(_scheduler.now()),
            ),
          );
          if (applied) {
            _addNotice('${song.name} is now available in your library.');
          }
        } else if (isImportTimedOut(
          createdAt: current.createdAt,
          now: _scheduler.now(),
        )) {
          final applied = await _updateExisting(
            scope,
            item.id,
            _attempts[item.id] ?? -1,
            DowntifyImportsCompanion(
              status: const Value('importTimedOut'),
              message: const Value('Jellyfin has not found this song yet.'),
              updatedAt: Value(_scheduler.now()),
            ),
          );
          if (applied) {
            _addNotice('Jellyfin has not found ${song.name} yet.', error: true);
          }
        }
      }
    } finally {
      if (_catalogLockEpoch == epoch) _catalogLockEpoch = null;
    }
  }

  // ------------------------------------------------------------------
  // Saved-progress recovery.
  // ------------------------------------------------------------------

  Future<void> _recoverSavedImports() async {
    final scope = _captureScope();
    if (scope == null || _disposed) return;
    var needsScan = false;
    for (final item in [...state.imports]) {
      if (!_scopeValid(scope)) return;
      if (item.downtifyUrl != scope.origin) continue;
      final saved = parseImportStatus(item.status);
      switch (saved.kind) {
        case ImportStatus.requestingScan:
          needsScan = true;
        case ImportStatus.submitting:
        case ImportStatus.retrying:
        case ImportStatus.queued:
        case ImportStatus.downloading:
        case ImportStatus.waitingForJellyfin:
        case ImportStatus.scanDenied:
        case ImportStatus.imported:
        case ImportStatus.downloadFailed:
        case ImportStatus.importTimedOut:
        case ImportStatus.unknown:
          break;
      }
    }
    if (!_scopeValid(scope)) return;
    // Retry counts, creation times, and notice flags are preserved:
    // recovery schedules work without rewriting rows.
    if (needsScan) _scheduleScanBatch();
    await poll();
  }

  // ------------------------------------------------------------------
  // Row persistence helpers.
  // ------------------------------------------------------------------

  Future<void> _loadImports(AccountLease? lease) async {
    lease ??= _scope.current;
    if (lease == null || _disposed) return;
    final session = lease.session;
    final imports = await ref
        .read(databaseProvider)
        .getDowntifyImports(session.serverId, session.userId);
    if (_disposed || !_scope.isCurrent(lease)) return;
    state = state.copyWith(imports: imports);
  }

  DowntifyImport? _currentRow(String id) =>
      state.imports.where((candidate) => candidate.id == id).firstOrNull;

  String _songName(DowntifyImport item) {
    try {
      return _songFromImport(item).name;
    } catch (_) {
      return 'Song';
    }
  }

  /// Scoped conditional row update through the account fence. Checks the
  /// scope and attempt token when the write starts; a zero-row result is
  /// stale or removed work and never recreates the row.
  Future<bool> _updateExisting(
    ImportScope scope,
    String id,
    int attempt,
    DowntifyImportsCompanion values,
  ) async {
    if (!_scopeValid(scope) || !_attemptCurrent(id, attempt)) return false;
    var affected = 0;
    final outcome = await _scope.commit(scope.lease, () async {
      if (!_scope.isCurrent(scope.lease) || !_attemptCurrent(id, attempt)) {
        return;
      }
      affected = await ref
          .read(databaseProvider)
          .updateDowntifyImportWhere(
            id: id,
            jellyfinServerId: scope.lease.session.serverId,
            jellyfinUserId: scope.lease.session.userId,
            origin: scope.origin,
            values: values,
          );
    });
    if (outcome == AccountWriteResult.stale) return false;
    if (!_scopeValid(scope) || !_attemptCurrent(id, attempt)) return false;
    if (affected == 0) return false;
    await _loadImports(scope.lease);
    return _scopeValid(scope) && _attemptCurrent(id, attempt);
  }

  Future<bool> _guardedRowRemove(
    ImportScope scope,
    String id,
    int attempt, {
    required String origin,
  }) async {
    if (!_scopeValid(scope) || !_attemptCurrent(id, attempt)) return false;
    var affected = 0;
    final outcome = await _scope.commit(scope.lease, () async {
      if (!_scope.isCurrent(scope.lease) || !_attemptCurrent(id, attempt)) {
        return;
      }
      affected = await ref
          .read(databaseProvider)
          .removeDowntifyImportWhere(
            id: id,
            jellyfinServerId: scope.lease.session.serverId,
            jellyfinUserId: scope.lease.session.userId,
            origin: origin,
          );
    });
    if (outcome == AccountWriteResult.stale) return false;
    if (!_scopeValid(scope) || !_attemptCurrent(id, attempt)) return false;
    return affected > 0;
  }

  DowntifySong _songFromImport(DowntifyImport item) =>
      DowntifySong.fromJson(jsonDecode(item.songJson) as Map<String, dynamic>);

  void _addNotice(String message, {bool error = false}) {
    if (_disposed) return;
    final notice = DowntifyNotice(
      '${_scheduler.now().microsecondsSinceEpoch}-${state.notices.length}',
      message,
      error: error,
    );
    state = state.copyWith(notices: [...state.notices, notice]);
  }
}
